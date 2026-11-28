import Foundation
import Supabase

enum BoardPresenceAPI {
    static func connect(
        client: SupabaseClient,
        boardID: UUID,
        userID: UUID,
        displayName: String
    ) async -> any BoardPresenceSession {
        let session = RealtimeBoardPresenceSession(
            client: client,
            boardID: boardID,
            userID: userID,
            displayName: displayName
        )
        await session.start()
        return session
    }
}

private actor RealtimeBoardPresenceSession: BoardPresenceSession {
    nonisolated let events: AsyncStream<BoardPresenceEvent>

    private let client: SupabaseClient
    private let boardID: UUID
    private let userID: UUID
    private let displayName: String
    private let continuation: AsyncStream<BoardPresenceEvent>.Continuation
    private var editingPhotoID: UUID?
    private var cursor: BoardCursorPosition?
    private var remoteStatesByRef: [String: PresenceStateDTO] = [:]
    private var channel: RealtimeChannelV2?
    private var producer: Task<Void, Never>?
    private var isStopped = false

    init(client: SupabaseClient, boardID: UUID, userID: UUID, displayName: String) {
        self.client = client
        self.boardID = boardID
        self.userID = userID
        self.displayName = displayName
        let pair = AsyncStream<BoardPresenceEvent>.makeStream()
        events = pair.stream
        continuation = pair.continuation
    }

    func start() {
        guard producer == nil, !isStopped else { return }
        continuation.onTermination = { [weak self] _ in
            Task { await self?.disconnect() }
        }
        producer = Task { [weak self] in
            await self?.run()
        }
    }

    func update(editingPhotoID: UUID?, cursor: BoardCursorPosition?) async {
        let editingChanged = self.editingPhotoID != editingPhotoID
        let cursorChanged = self.cursor != cursor
        self.editingPhotoID = editingPhotoID
        self.cursor = cursor
        if editingChanged {
            emitMembers()
        }
        guard let channel, channel.status == .subscribed else { return }
        if editingChanged {
            try? await channel.track(localState)
        }
        if cursorChanged {
            await broadcastCursor(on: channel)
        }
    }

    func disconnect() async {
        guard !isStopped else { return }
        isStopped = true
        producer?.cancel()
        producer = nil

        if let channel {
            if channel.status == .subscribed {
                cursor = nil
                await broadcastCursor(on: channel)
                await channel.untrack()
            }
            self.channel = nil
            await client.removeChannel(channel)
        }
        remoteStatesByRef.removeAll()
        continuation.finish()
    }

    private func run() async {
        while !Task.isCancelled, !isStopped {
            continuation.yield(.connecting)
            emitMembers()

            let channel = client.channel(liveTopic) { config in
                config.isPrivate = true
                config.presence.key = userID.uuidString.lowercased()
            }
            self.channel = channel
            let statuses = channel.statusChange
            let presenceChanges = channel.presenceChange()
            let cursorMessages = channel.broadcastStream(event: "cursor")

            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask { [weak self] in
                        for await status in statuses {
                            guard !Task.isCancelled else { return }
                            await self?.handle(status, channel: channel)
                        }
                    }
                    group.addTask { [weak self] in
                        for await action in presenceChanges {
                            guard !Task.isCancelled else { return }
                            await self?.handle(action, channel: channel)
                        }
                    }
                    group.addTask { [weak self] in
                        for await message in cursorMessages {
                            guard !Task.isCancelled else { return }
                            await self?.handleCursor(message, channel: channel)
                        }
                    }

                    try await channel.subscribeWithError()
                    try await group.waitForAll()
                }
            } catch is CancellationError {
                await remove(channel)
                break
            } catch {
                remoteStatesByRef.removeAll()
                emitMembers()
                continuation.yield(.remoteCursorsCleared)
                continuation.yield(.connectionFailed)
            }

            await remove(channel)
            guard !Task.isCancelled, !isStopped else { break }
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                break
            }
        }

        continuation.finish()
    }

    private func handle(_ status: RealtimeChannelStatus, channel: RealtimeChannelV2) async {
        guard self.channel === channel, !isStopped else { return }
        switch status {
        case .subscribing:
            remoteStatesByRef.removeAll()
            continuation.yield(.connecting)
            continuation.yield(.remoteCursorsCleared)
            emitMembers()
        case .subscribed:
            try? await channel.track(localState)
            await broadcastCursor(on: channel)
            continuation.yield(.connected)
            emitMembers()
        case .unsubscribed, .unsubscribing:
            break
        }
    }

    private func handle(_ action: any PresenceAction, channel: RealtimeChannelV2) {
        guard self.channel === channel, !isStopped else { return }

        for presence in action.leaves.values {
            remoteStatesByRef[presence.ref] = nil
        }
        for presence in action.joins.values {
            if let state = try? presence.decodeState(as: PresenceStateDTO.self), state.userID != userID {
                remoteStatesByRef[presence.ref] = state
            }
        }
        emitMembers()
    }

    private func handleCursor(_ message: JSONObject, channel: RealtimeChannelV2) {
        guard self.channel === channel, !isStopped,
              let payload = message["payload"]?.objectValue,
              let data = try? JSONEncoder().encode(payload),
              let update = try? JSONDecoder().decode(CursorDTO.self, from: data),
              update.userID != userID
        else { return }

        let position: BoardCursorPosition? = if update.active, let x = update.x, let y = update.y {
            BoardCursorPosition(x: x, y: y)
        } else {
            nil
        }
        continuation.yield(.cursorChanged(userID: update.userID, position: position))
    }

    private func remove(_ channel: RealtimeChannelV2) async {
        guard self.channel === channel else { return }
        self.channel = nil
        await client.removeChannel(channel)
    }

    private func emitMembers() {
        var membersByID = [
            userID: BoardEditingMember(
                id: userID,
                displayName: displayName,
                editingPhotoID: editingPhotoID
            )
        ]

        for state in remoteStatesByRef.values {
            let member = state.member
            if let existing = membersByID[member.id], existing.editingPhotoID != nil,
               member.editingPhotoID == nil {
                continue
            }
            membersByID[member.id] = member
        }

        let members = membersByID.values.sorted {
            if $0.id == userID { return true }
            if $1.id == userID { return false }
            let comparison = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
            return comparison == .orderedSame ? $0.id.uuidString < $1.id.uuidString : comparison == .orderedAscending
        }
        continuation.yield(.membersChanged(members))
    }

    private var localState: PresenceStateDTO {
        PresenceStateDTO(
            userID: userID,
            displayName: displayName,
            editingPhotoID: editingPhotoID
        )
    }

    private func broadcastCursor(on channel: RealtimeChannelV2) async {
        guard self.channel === channel, channel.status == .subscribed else { return }
        let update = CursorDTO(
            userID: userID,
            x: cursor?.x,
            y: cursor?.y,
            active: cursor != nil,
            sentAt: Date().ISO8601Format()
        )
        try? await channel.broadcast(event: "cursor", message: update)
    }

    private var liveTopic: String {
        "board:\(boardID.uuidString.lowercased()):live"
    }
}

private struct PresenceStateDTO: Codable, Sendable {
    let userID: UUID
    let displayName: String
    let editingPhotoID: UUID?

    private enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case editingPhotoID = "editing_photo_id"
    }

    var member: BoardEditingMember {
        BoardEditingMember(id: userID, displayName: displayName, editingPhotoID: editingPhotoID)
    }
}

private struct CursorDTO: Codable, Sendable {
    let userID: UUID
    let x: Double?
    let y: Double?
    let active: Bool
    let sentAt: String

    private enum CodingKeys: String, CodingKey {
        case x, y, active
        case userID = "user_id"
        case sentAt = "sent_at"
    }
}
