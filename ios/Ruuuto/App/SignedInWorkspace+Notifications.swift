import Foundation

enum NotificationRoutingFailure: Equatable, Sendable {
    case membershipUnavailable
}

enum NotificationRoutingState: Equatable, Sendable {
    case idle
    case checking(attemptID: UUID)
    case failed(tapID: UUID, NotificationRoutingFailure)
}

extension SignedInWorkspace {
    var notificationRoutingFailure: NotificationRoutingFailure? {
        guard case let .failed(tapID, failure) = notificationRoutingState,
              notifications.pendingTap?.id == tapID else { return nil }
        return failure
    }

    func showNotificationSettings() {
        guard isCurrentSession else { return }
        navigate(to: .notifications)
    }

    func closeNotificationSettings() {
        guard case .notifications = destination else { return }
        returnToSelectedBoard()
    }

    func retryPendingNotification() async {
        guard notificationRoutingFailure != nil else { return }
        await openPendingNotification()
    }

    func openPendingNotification() async {
        guard isCurrentSession, !isSigningOut, !Task.isCancelled,
              let event = notifications.pendingTap else { return }

        let attempt = NotificationRoutingState.checking(attemptID: UUID())
        notificationRoutingState = attempt
        defer {
            if notificationRoutingState == attempt {
                notificationRoutingState = .idle
            }
        }

        let memberships: [BoardGroup]
        do {
            memberships = try await GroupDirectoryAPI.list(client: session.client)
        } catch is CancellationError {
            return
        } catch {
            guard canApplyNotificationRoute(event, attempt: attempt) else { return }
            notificationRoutingState = .failed(tapID: event.id, .membershipUnavailable)
            return
        }

        guard canApplyNotificationRoute(event, attempt: attempt) else { return }
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
              destinationGroupID == groupID else { return }

        switch currentBoard.state(for: groupID) {
        case .loaded(let activeBoard) where activeBoard.id == boardID:
            navigate(to: .board(groupID: groupID))
        case .loaded, .empty:
            navigate(to: .historicalBoard(groupID: groupID, boardID: boardID))
        default:
            break
        }
    }

    private func canApplyNotificationRoute(_ event: NotificationTapEvent, attempt: NotificationRoutingState) -> Bool {
        isCurrentSession && !isSigningOut && !Task.isCancelled
            && notifications.pendingTap == event && notificationRoutingState == attempt
    }
}
