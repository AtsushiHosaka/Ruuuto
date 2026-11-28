import Foundation
import Observation

@MainActor
@Observable
final class SignedInWorkspace {
    enum Destination: Equatable {
        case groups
        case createGroup
        case board(groupID: UUID, boardID: UUID?)
    }

    let groups: GroupDirectoryViewModel
    let currentBoard: CurrentBoardViewModel
    private let session: SessionModel
    var profile: ProfileViewModel { session.profile }
    private let userID: UUID
    private let defaults: UserDefaults
    private(set) var destination: Destination = .groups
    private(set) var boardLoadRequestID: UUID?
    private(set) var isSigningOut = false
    private(set) var groupCreation: CreateGroupViewModel?
    @ObservationIgnored private var groupCreationID: UUID?

    init(session: SessionModel, userID: UUID, defaults: UserDefaults = .standard) {
        self.session = session
        self.userID = userID
        self.defaults = defaults
        let client = session.client
        groups = GroupDirectoryViewModel(loadGroups: { try await GroupDirectoryAPI.list(client: client) })
        currentBoard = CurrentBoardViewModel(loadBoard: { try await CurrentBoardAPI.load(client: client, groupID: $0) })
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

    func showGroupCreation() {
        guard isCurrentSession else { return }
        let creationID = UUID()
        let client = session.client
        groupCreationID = creationID
        groupCreation = CreateGroupViewModel(
            createGroup: { name, requestID in
                try await CreateGroupAPI.create(client: client, name: name, requestID: requestID)
            },
            selectGroup: { [weak self] group in
                guard let self, self.isCurrentSession, self.destination == .createGroup,
                      self.groupCreationID == creationID else { return }
                self.groups.selectGroup(group)
                self.openBoard(groupID: group.id)
            }
        )
        destination = .createGroup
    }

    /// 開催中のボードへ写真を投稿する画面の状態（RCNO-13）
    func makePhotoPost(boardID: UUID) -> PhotoPostViewModel {
        PhotoPostViewModel(
            boardID: boardID,
            poster: PhotoPostAPI.poster(client: session.client),
            pendingStore: PendingPhotoStore.forUser(userID)
        )
    }

    func showGroups() {
        groupCreation = nil
        groupCreationID = nil
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
        groupCreation = nil
        groupCreationID = nil
        groups.selectGroup(id: groupID)
        defaults.set(groupID.uuidString, forKey: groupSelectionKey)
        destination = .board(groupID: groupID, boardID: boardID)
        boardLoadRequestID = UUID()
    }
}
