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
        self.editingPhotoID = editingPhotoID
        self.cursor = cursor
        emitMembers()
        guard let channel, channel.status == .subscribed else { return }
        try? await channel.track(localState)
    }

    func disconnect() async {
        guard !isStopped else { return }
        isStopped = true
        producer?.cancel()
        producer = nil

        if let channel {
            self.channel = nil
            if channel.status == .subscribed {
                await channel.untrack()
            }
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

                    try await channel.subscribeWithError()
                    try await group.waitForAll()
                }
            } catch is CancellationError {
                await remove(channel)
                break
            } catch {
                remoteStatesByRef.removeAll()
                emitMembers()
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
            emitMembers()
        case .subscribed:
            try? await channel.track(localState)
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
                editingPhotoID: editingPhotoID,
                cursor: cursor
            )
        ]

        for state in remoteStatesByRef.values {
            let member = state.member
            if let existing = membersByID[member.id], presenceScore(existing) > presenceScore(member) {
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
            editingPhotoID: editingPhotoID,
            cursorX: cursor?.x,
            cursorY: cursor?.y
        )
    }

    private func presenceScore(_ member: BoardEditingMember) -> Int {
        (member.editingPhotoID == nil ? 0 : 2) + (member.cursor == nil ? 0 : 1)
    }

    private var liveTopic: String {
        "board:\(boardID.uuidString.lowercased()):live"
    }
}

private struct PresenceStateDTO: Codable, Sendable {
    let userID: UUID
    let displayName: String
    let editingPhotoID: UUID?
    let cursorX: Double?
    let cursorY: Double?

    private enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case editingPhotoID = "editing_photo_id"
        case cursorX = "cursor_x"
        case cursorY = "cursor_y"
    }

    var member: BoardEditingMember {
        let cursor: BoardCursorPosition? = if let cursorX, let cursorY {
            BoardCursorPosition(x: cursorX, y: cursorY)
        } else {
            nil
        }
        return BoardEditingMember(
            id: userID,
            displayName: displayName,
            editingPhotoID: editingPhotoID,
            cursor: cursor
        )
    }
}
