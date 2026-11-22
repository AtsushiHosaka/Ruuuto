import Foundation

struct InvitationAcceptance: Equatable, Sendable {
    enum Membership: Equatable, Sendable {
        case joined
        case alreadyMember
    }

    let groupID: UUID
    let membership: Membership
}
