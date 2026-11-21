import Foundation
import Observation

@MainActor
@Observable
final class SignedInWorkspace {
    enum Destination: Equatable {
        case groups
        case board(groupID: UUID, boardID: UUID?)
    }

    let groups: GroupDirectoryViewModel
    private let session: SessionModel
    private let userID: UUID
    private let defaults: UserDefaults
    private(set) var destination: Destination = .groups
    private(set) var isSigningOut = false

    init(session: SessionModel, userID: UUID, defaults: UserDefaults = .standard) {
        self.session = session
        self.userID = userID
        self.defaults = defaults
        let client = session.client
        groups = GroupDirectoryViewModel(loadGroups: { try await GroupDirectoryAPI.list(client: client) })
    }

    func start() async {
        await groups.refresh()
        guard isCurrentSession, !Task.isCancelled, groups.loadState == .loaded, destination == .groups,
              groups.selectedID == nil else { return }

        let previous = defaults.string(forKey: groupSelectionKey).flatMap { UUID(uuidString: $0) }
        if let previous, selectGroup(previous) {
            return
        }

        if groups.groups.count == 1, let group = groups.groups.first {
            selectGroup(group.id)
        }
    }

    @discardableResult
    func selectGroup(_ groupID: UUID) -> Bool {
        guard isCurrentSession, groups.groups.contains(where: { $0.id == groupID }) else { return false }
        openBoard(groupID: groupID)
        return true
    }

    func showGroups() {
        destination = .groups
    }

    func signOut() async throws {
        guard isCurrentSession, !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        try await session.signOut()
    }

    private var isCurrentSession: Bool {
        session.state == .signedIn(userID)
    }

    private var groupSelectionKey: String {
        "ruuuto.lastGroup.\(userID.uuidString)"
    }

    private func openBoard(groupID: UUID, boardID: UUID? = nil) {
        guard isCurrentSession else { return }
        groups.selectGroup(id: groupID)
        defaults.set(groupID.uuidString, forKey: groupSelectionKey)
        destination = .board(groupID: groupID, boardID: boardID)
    }
}
