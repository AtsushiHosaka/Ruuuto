import Foundation
import Observation

@MainActor
@Observable
final class InvitationCoordinator {
    private(set) var pending: InvitationLink?

    private let origin: URL
    private let pathPrefix: String

    init(origin: URL, pathPrefix: String) {
        self.origin = origin
        self.pathPrefix = pathPrefix
    }

    // Call from onOpenURL. The pending link is kept across changes to sign-in state.
    func receive(_ url: URL) {
        guard let link = InvitationLink(url: url, allowedOrigin: origin, pathPrefix: pathPrefix) else { return }
        pending = link
    }

    func accept(
        _ link: InvitationLink,
        using join: (String) async throws -> UUID
    ) async throws -> UUID? {
        guard pending == link else { return nil }
        let groupID = try await join(link.token)
        guard pending == link else { return nil }
        pending = nil
        return groupID
    }

    func discard(_ link: InvitationLink) {
        guard pending == link else { return }
        pending = nil
    }
}
