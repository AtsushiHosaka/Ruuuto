import Foundation

extension SignedInWorkspace {
    func showNotificationSettings() {
        guard isCurrentSession else { return }
        navigate(to: .notifications)
    }

    func closeNotificationSettings() {
        guard case .notifications = destination else { return }
        returnToSelectedBoard()
    }

    func openPendingNotification() async {
        guard isCurrentSession, !isSigningOut, let event = notifications.pendingTap else { return }

        let memberships: [BoardGroup]
        do {
            memberships = try await GroupDirectoryAPI.list(client: session.client)
        } catch {
            return
        }

        guard isCurrentSession, !isSigningOut, !Task.isCancelled,
              notifications.pendingTap == event else { return }
        let groupID = event.destination.groupID
        let boardID = event.destination.boardID
        guard let group = memberships.first(where: { $0.id == groupID }) else {
            notifications.acknowledgeTap(event)
            return
        }

        groups.selectGroup(group)
        openBoard(groupID: groupID, boardID: boardID)
        // Opening the board starts a separate task, so consuming the tap cannot cancel its load.
        notifications.acknowledgeTap(event)
    }

    func loadSelectedBoard(_ groupID: UUID?) async {
        await currentBoard.selectGroup(groupID)
        guard isCurrentSession, !Task.isCancelled,
              let groupID, groups.selectedID == groupID,
              case let .notificationBoard(destinationGroupID, boardID) = destination,
              destinationGroupID == groupID,
              case let .loaded(activeBoard) = currentBoard.state(for: groupID) else { return }
        if activeBoard.id == boardID {
            navigate(to: .board(groupID: groupID))
        } else {
            navigate(to: .historicalBoard(groupID: groupID, boardID: boardID))
        }
    }
}
