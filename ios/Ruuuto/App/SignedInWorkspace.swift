import Foundation
import Observation

@MainActor
@Observable
final class SignedInWorkspace {
    enum Destination {
        case groups
        case createGroup(id: UUID, model: CreateGroupViewModel)
        case editTopic(TopicEditorViewModel)
        case invitation
        case inviteSharing
        case notifications
        case board(groupID: UUID)
        case notificationBoard(groupID: UUID, boardID: UUID)
        case historicalBoard(groupID: UUID, boardID: UUID)
    }

    struct SharedInvitation: Identifiable {
        let id = UUID()
        let url: URL
    }

    let notifications: NotificationSettingsViewModel
    let invitation: InvitationViewModel?
    let invitationShare: InvitationShareViewModel
    var sharedInvitation: SharedInvitation?
    let groups: GroupDirectoryViewModel
    let currentBoard: CurrentBoardViewModel
    let session: SessionModel
    let userID: UUID
    private let defaults: UserDefaults
    private(set) var destination: Destination = .groups
    private(set) var isSigningOut = false
    var topicEditor: TopicEditorViewModel? {
        guard case .editTopic(let editor) = destination else { return nil }
        return editor
    }

    var groupCreation: CreateGroupViewModel? {
        guard case .createGroup(_, let model) = destination else { return nil }
        return model
    }

    init(
        session: SessionModel,
        userID: UUID,
        invitationOrigin: URL?,
        notificationDelegate: NotificationAppDelegate,
        defaults: UserDefaults = .standard
    ) {
        self.session = session
        self.userID = userID
        self.defaults = defaults
        let client = session.client
        let installationID = Self.installationID(in: defaults)
        notifications = NotificationSettingsViewModel(
            notifications: notificationDelegate,
            decodeDestination: NotificationDeviceAPI.decodeDestination,
            synchronizeDevice: { [weak session] expectedUserID, registration in
                guard session?.state == .signedIn(expectedUserID) else { throw CancellationError() }
                try await NotificationDeviceAPI.synchronize(
                    client: client, installationID: installationID, registration: registration
                )
            }
        )
        let invitationAPI = InvitationAPI(client: client)
        invitation = InvitationLink.allowedHTTPSOrigin(invitationOrigin).map {
            InvitationViewModel(
                coordinator: InvitationCoordinator(origin: $0, pathPrefix: InvitationLink.pathPrefix),
                join: invitationAPI.accept(token:)
            )
        }
        invitationShare = InvitationShareViewModel(origin: invitationOrigin, issue: invitationAPI.issue(groupID:))
        groups = GroupDirectoryViewModel(loadGroups: { try await GroupDirectoryAPI.list(client: client) })
        currentBoard = CurrentBoardViewModel(loadBoard: { try await CurrentBoardAPI.load(client: client, groupID: $0) })
    }

    func start() async {
        guard isCurrentSession, !Task.isCancelled else { return }
        invitation?.setSignedInUser(userID)
        notifications.setSignedInUser(userID)
        await notifications.resumeRemoteDelivery()
        await groups.refresh()
        guard isCurrentSession, !Task.isCancelled, groups.loadState == .loaded, case .groups = destination,
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
        navigate(to: .groups)
    }

    func returnToSelectedBoard() {
        if let groupID = groups.selectedID {
            openBoard(groupID: groupID)
        } else {
            showGroups()
        }
    }

    func navigate(to next: Destination) {
        switch (destination, next) {
        case (.invitation, .invitation), (.inviteSharing, .inviteSharing):
            break
        case (.invitation, _):
            invitation?.discard()
        case (.inviteSharing, _):
            invitationShare.selectGroup(nil)
        default:
            break
        }
        sharedInvitation = nil
        destination = next
    }

    func signOut() async throws {
        guard isCurrentSession, !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        do {
            try await notifications.unregisterBeforeSignOut()
        } catch {
            // The device stops receiving pushes locally even when the server is unreachable.
        }
        guard isCurrentSession else { return }
        notifications.setSignedInUser(nil)
        notifications.pauseRemoteDelivery()
        do {
            try await session.signOut()
        } catch {
            // Supabase removes its local session before revoking it remotely.
            if isCurrentSession, session.client.auth.currentSession != nil {
                notifications.setSignedInUser(userID)
                await notifications.resumeRemoteDelivery()
                throw error
            }
        }
        invitation?.setSignedInUser(nil)
    }

    private static func installationID(in defaults: UserDefaults) -> UUID {
        let key = "ruuuto.notificationInstallation"
        if let stored = defaults.string(forKey: key).flatMap({ UUID(uuidString: $0) }) {
            return stored
        }
        let id = UUID()
        defaults.set(id.uuidString, forKey: key)
        return id
    }

    var isCurrentSession: Bool {
        session.state == .signedIn(userID)
    }

    private var groupSelectionKey: String {
        "ruuuto.lastGroup.\(userID.uuidString)"
    }

    func openBoard(groupID: UUID, boardID: UUID? = nil) {
        guard isCurrentSession else { return }
        groups.selectGroup(id: groupID)
        defaults.set(groupID.uuidString, forKey: groupSelectionKey)
        if let boardID {
            navigate(to: .notificationBoard(groupID: groupID, boardID: boardID))
        } else {
            navigate(to: .board(groupID: groupID))
        }
    }
}
