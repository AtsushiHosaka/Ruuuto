import Foundation
import Observation

@MainActor
@Observable
final class InvitationShareViewModel {
    enum State: Equatable {
        case idle
        case unavailable
        case issuing
        case ready(URL)
        case failed
    }

    let origin: URL?
    private let issue: (UUID) async throws -> String
    private var groupID: UUID?
    private var attemptID: UUID?

    private(set) var state: State = .idle

    var shareURL: URL? {
        guard case .ready(let url) = state else { return nil }
        return url
    }

    init(origin: URL?, issue: @escaping (UUID) async throws -> String) {
        self.origin = InvitationLink.allowedHTTPSOrigin(origin)
        self.issue = issue
    }

    func selectGroup(_ groupID: UUID?) {
        guard self.groupID != groupID else { return }
        self.groupID = groupID
        cancel()
    }

    func requestLink() async {
        guard let groupID, let origin, state != .issuing, !Task.isCancelled else { return }
        let attempt = UUID()
        attemptID = attempt
        state = .issuing

        do {
            let token = try await issue(groupID)
            try Task.checkCancellation()
            guard attemptID == attempt else { return }
            if let invitation = InvitationLink(token: token, origin: origin) {
                state = .ready(invitation.url)
            } else {
                state = .failed
            }
        } catch {
            guard attemptID == attempt else { return }
            state = Task.isCancelled || error is CancellationError ? .idle : .failed
        }
        attemptID = nil
    }

    func cancel() {
        attemptID = nil
        state = groupID != nil && origin == nil ? .unavailable : .idle
    }
}
