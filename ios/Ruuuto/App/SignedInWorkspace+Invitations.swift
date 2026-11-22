import Foundation

extension SignedInWorkspace {
    func receiveInvitation(_ url: URL) {
        guard isCurrentSession, let invitation else { return }
        invitation.setSignedInUser(userID)
        invitation.receive(url)
        clearInvitationAcceptance()
        guard invitation.state == .ready else { return }
        navigate(to: .invitation)
    }

    func acceptInvitation() async {
        guard isCurrentSession, case .invitation = destination, let invitation else { return }
        await invitation.accept()
        guard isCurrentSession, !Task.isCancelled, case .invitation = destination,
              let acceptance = invitation.takeAcceptance() else { return }
        openAcceptedInvitation(acceptance)
        await groups.refresh()
    }

    func showInvitationSharing() {
        guard isCurrentSession, let groupID = groups.selectedID,
              groups.groups.contains(where: { $0.id == groupID }) else { return }
        invitationShare.selectGroup(groupID)
        navigate(to: .inviteSharing)
    }

    func shareInvitation() {
        guard isCurrentSession, case .inviteSharing = destination, let url = invitationShare.shareURL else { return }
        sharedInvitation = SharedInvitation(url: url)
    }

    func closeInvitation() {
        switch destination {
        case .invitation, .inviteSharing:
            returnToSelectedBoard()
        default:
            break
        }
    }
}
