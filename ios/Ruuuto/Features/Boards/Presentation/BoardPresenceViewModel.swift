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

    let currentUserID: UUID
    private let connect: @MainActor (UUID, String) async -> any BoardPresenceSession
    @ObservationIgnored private var session: (any BoardPresenceSession)?
    @ObservationIgnored private var synchronizationID: UUID?
    @ObservationIgnored private var updateTask: Task<Void, Never>?

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
        let previousSession = session
        session = nil
        await previousSession?.disconnect()
        guard self.synchronizationID == synchronizationID, !Task.isCancelled else { return }

        editingPhotoID = nil
        members = [
            BoardEditingMember(
                id: currentUserID,
                displayName: displayName,
                editingPhotoID: editingPhotoID
            )
        ]
        state = .connecting

        let session = await connect(boardID, displayName)
        guard self.synchronizationID == synchronizationID, !Task.isCancelled else {
            await session.disconnect()
            return
        }
        self.session = session
        await session.setEditingPhotoID(editingPhotoID)

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
            members = []
            state = .idle
        }
    }

    func setEditingPhotoID(_ photoID: UUID?) {
        guard editingPhotoID != photoID else { return }
        editingPhotoID = photoID
        if let index = members.firstIndex(where: { $0.id == currentUserID }) {
            let current = members[index]
            members[index] = BoardEditingMember(
                id: current.id,
                displayName: current.displayName,
                editingPhotoID: photoID
            )
        }

        guard let session else { return }
        let previousUpdate = updateTask
        updateTask = Task {
            await previousUpdate?.value
            guard !Task.isCancelled else { return }
            await session.setEditingPhotoID(photoID)
        }
    }
}
