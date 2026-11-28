import Foundation
import Observation

enum BoardPresenceState: Equatable, Sendable {
    case idle
    case connecting
    case connected
    case reconnecting
}

@MainActor
@Observable
final class BoardPresenceViewModel {
    private(set) var members: [BoardEditingMember] = []
    private(set) var state: BoardPresenceState = .idle
    private(set) var editingPhotoID: UUID?
    private(set) var cursor: BoardCursorPosition?

    let currentUserID: UUID
    private let connect: @MainActor (UUID, String) async -> any BoardPresenceSession
    @ObservationIgnored private var session: (any BoardPresenceSession)?
    @ObservationIgnored private var synchronizationID: UUID?
    @ObservationIgnored private var updateTask: Task<Void, Never>?
    @ObservationIgnored private var pendingUpdate: PresenceUpdate?

    init(
        currentUserID: UUID,
        connect: @escaping @MainActor (UUID, String) async -> any BoardPresenceSession
    ) {
        self.currentUserID = currentUserID
        self.connect = connect
    }

    func synchronize(boardID: UUID, displayName: String) async {
        let synchronizationID = UUID()
        self.synchronizationID = synchronizationID
        updateTask?.cancel()
        updateTask = nil
        pendingUpdate = nil
        let previousSession = session
        session = nil
        await previousSession?.disconnect()
        guard self.synchronizationID == synchronizationID, !Task.isCancelled else { return }

        editingPhotoID = nil
        cursor = nil
        members = [
            BoardEditingMember(
                id: currentUserID,
                displayName: displayName,
                editingPhotoID: editingPhotoID,
                cursor: cursor
            )
        ]
        state = .connecting

        let session = await connect(boardID, displayName)
        guard self.synchronizationID == synchronizationID, !Task.isCancelled else {
            await session.disconnect()
            return
        }
        self.session = session
        await session.update(editingPhotoID: editingPhotoID, cursor: cursor)

        await withTaskCancellationHandler {
            for await event in session.events {
                guard self.synchronizationID == synchronizationID, !Task.isCancelled else { break }
                switch event {
                case .connecting:
                    state = state == .connected ? .reconnecting : .connecting
                case .connected:
                    state = .connected
                case .connectionFailed:
                    state = state == .connected ? .reconnecting : .connecting
                case .membersChanged(let members):
                    self.members = members
                }
            }
        } onCancel: {
            Task { await session.disconnect() }
        }

        await session.disconnect()
        if self.synchronizationID == synchronizationID {
            self.session = nil
            editingPhotoID = nil
            cursor = nil
            members = []
            state = .idle
        }
    }

    func setEditingPhotoID(_ photoID: UUID?) {
        guard editingPhotoID != photoID else { return }
        editingPhotoID = photoID
        updateCurrentMember()
        enqueuePresenceUpdate()
    }

    func setCursor(_ cursor: BoardCursorPosition?) {
        guard self.cursor != cursor else { return }
        self.cursor = cursor
        updateCurrentMember()
        enqueuePresenceUpdate()
    }

    private func updateCurrentMember() {
        if let index = members.firstIndex(where: { $0.id == currentUserID }) {
            let current = members[index]
            members[index] = BoardEditingMember(
                id: current.id,
                displayName: current.displayName,
                editingPhotoID: editingPhotoID,
                cursor: cursor
            )
        }
    }

    private func enqueuePresenceUpdate() {
        guard let session else { return }
        pendingUpdate = PresenceUpdate(editingPhotoID: editingPhotoID, cursor: cursor)
        guard updateTask == nil else { return }
        updateTask = Task {
            while !Task.isCancelled, let update = pendingUpdate {
                pendingUpdate = nil
                await session.update(editingPhotoID: update.editingPhotoID, cursor: update.cursor)
                if pendingUpdate != nil {
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
            updateTask = nil
        }
    }
}

private struct PresenceUpdate: Equatable, Sendable {
    let editingPhotoID: UUID?
    let cursor: BoardCursorPosition?
}
