import Foundation
import Observation

@MainActor
@Observable
final class SignedInWorkspace {
    enum Destination: Equatable {
        case groups
        case createGroup
        case editTopic
        case invitation
        case inviteSharing
        case notifications
        case board(groupID: UUID, boardID: UUID?)
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
    private let session: SessionModel
    private let userID: UUID
    private let defaults: UserDefaults
    private(set) var destination: Destination = .groups
    private(set) var isSigningOut = false
    private(set) var topicEditor: TopicEditorViewModel?
    private(set) var groupCreation: CreateGroupViewModel?
    @ObservationIgnored private var groupCreationID: UUID?

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
        invitation?.setSignedInUser(userID)
        notifications.setSignedInUser(userID)
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
            createGroup: { try await CreateGroupAPI.create(client: client, name: $0) },
            selectGroup: { [weak self] group in
                guard let self, self.isCurrentSession, self.destination == .createGroup,
                      self.groupCreationID == creationID else { return }
                self.groups.selectGroup(group)
                self.openBoard(groupID: group.id)
            }
        )
        destination = .createGroup
    }

    func showTopicEditor() {
        guard isCurrentSession,
              case let .board(groupID, boardID) = destination,
              case let .loaded(board) = currentBoard.state(for: groupID),
              boardID == nil || boardID == board.id else { return }

        let client = session.client
        topicEditor = TopicEditorViewModel(
            board: board,
            saveTopic: { try await TopicEditorAPI.save(client: client, boardID: $0, topic: $1) },
            reloadBoard: { [weak self] id in
                guard let self, self.isCurrentSession else { return }
                await self.currentBoard.reload(for: id)
            }
        )
        destination = .editTopic
    }

    func saveTopic() async {
        guard isCurrentSession, destination == .editTopic, let editor = topicEditor else { return }
        guard await editor.saveChanges(), isCurrentSession, !Task.isCancelled,
              destination == .editTopic, topicEditor === editor else { return }
        closeTopicEditor()
    }

    func closeTopicEditor() {
        guard destination == .editTopic, let editor = topicEditor else { return }
        openBoard(groupID: editor.board.groupID)
    }

    func receiveInvitation(_ url: URL) {
        guard isCurrentSession, let invitation else { return }
        invitation.setSignedInUser(userID)
        invitation.receive(url)
        guard invitation.state == .ready else { return }
        invitationShare.selectGroup(nil)
        sharedInvitation = nil
        destination = .invitation
    }

    func acceptInvitation() async {
        guard isCurrentSession, destination == .invitation, let invitation else { return }
        await invitation.accept()
        guard isCurrentSession, !Task.isCancelled, destination == .invitation,
              let groupID = invitation.takeAcceptedGroupID() else { return }
        openBoard(groupID: groupID)
        await groups.refresh()
    }

    func showInvitationSharing() {
        guard isCurrentSession, let groupID = groups.selectedID,
              groups.groups.contains(where: { $0.id == groupID }) else { return }
        invitationShare.selectGroup(groupID)
        destination = .inviteSharing
    }

    func shareInvitation() {
        guard isCurrentSession, destination == .inviteSharing, let url = invitationShare.shareURL else { return }
        sharedInvitation = SharedInvitation(url: url)
    }

    func closeInvitation() {
        guard destination == .invitation || destination == .inviteSharing else { return }
        if let groupID = groups.selectedID {
            openBoard(groupID: groupID)
        } else {
            showGroups()
        }
    }

    func showNotificationSettings() {
        guard isCurrentSession else { return }
        clearInvitationFlow()
        destination = .notifications
    }

    func closeNotificationSettings() {
        guard destination == .notifications else { return }
        if let groupID = groups.selectedID {
            openBoard(groupID: groupID)
        } else {
            showGroups()
        }
    }

    func openPendingNotification() async {
        guard isCurrentSession, let event = notifications.pendingTap else { return }
        await groups.refresh()
        guard isCurrentSession, !Task.isCancelled, notifications.pendingTap == event,
              groups.loadState == .loaded else { return }

        if groups.groups.contains(where: { $0.id == event.destination.groupID }) {
            openBoard(groupID: event.destination.groupID, boardID: event.destination.boardID)
        }
        notifications.acknowledgeTap(event)
    }

    private func clearInvitationFlow() {
        if destination == .invitation {
            invitation?.discard()
        }
        invitationShare.selectGroup(nil)
        sharedInvitation = nil
    }

    func showGroups() {
        clearInvitationFlow()
        topicEditor = nil
        groupCreation = nil
        groupCreationID = nil
        destination = .groups
    }

    func signOut() async throws {
        guard isCurrentSession, !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        try await notifications.unregisterBeforeSignOut()
        do {
            try await session.signOut()
        } catch {
            notifications.resumeAfterFailedSignOut()
            throw error
        }
        notifications.setSignedInUser(nil)
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

    private var isCurrentSession: Bool {
        session.state == .signedIn(userID)
    }

    private var groupSelectionKey: String {
        "ruuuto.lastGroup.\(userID.uuidString)"
    }

    private func openBoard(groupID: UUID, boardID: UUID? = nil) {
        guard isCurrentSession else { return }
        clearInvitationFlow()
        topicEditor = nil
        groupCreation = nil
        groupCreationID = nil
        groups.selectGroup(id: groupID)
        defaults.set(groupID.uuidString, forKey: groupSelectionKey)
        destination = .board(groupID: groupID, boardID: boardID)
    }
}
