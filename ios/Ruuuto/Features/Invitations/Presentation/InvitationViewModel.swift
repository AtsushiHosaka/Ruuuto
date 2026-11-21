import Foundation
import Observation

enum InvitationJoinError: Error {
    case invalid
    case expired
}

@MainActor
@Observable
final class InvitationViewModel {
    enum State: Equatable {
        case idle
        case waitingForSignIn
        case ready
        case joining
        case accepted(UUID)
        case invalid
        case expired
        case failed
    }

    private let coordinator: InvitationCoordinator
    private let join: (String) async throws -> UUID
    private var signedInUserID: UUID?
    private var attemptID: UUID?

    private(set) var state: State = .idle

    init(coordinator: InvitationCoordinator, join: @escaping (String) async throws -> UUID) {
        self.coordinator = coordinator
        self.join = join
    }

    func receive(_ url: URL) {
        let previous = coordinator.pending
        coordinator.receive(url)
        if coordinator.pending != previous {
            resetState()
        }
    }

    func setSignedInUser(_ userID: UUID?) {
        guard signedInUserID != userID else { return }
        signedInUserID = userID
        resetState()
    }

    func accept() async {
        guard let userID = signedInUserID,
              let link = coordinator.pending,
              state == .ready || state == .failed else { return }

        let attempt = UUID()
        attemptID = attempt
        state = .joining

        do {
            let groupID = try await coordinator.accept(link) { token in
                try Task.checkCancellation()
                let groupID = try await join(token)
                try Task.checkCancellation()
                guard attemptID == attempt, signedInUserID == userID else {
                    throw CancellationError()
                }
                return groupID
            }
            guard attemptID == attempt else { return }
            if let groupID {
                state = .accepted(groupID)
            } else {
                resetState()
            }
        } catch {
            guard attemptID == attempt else { return }
            switch error {
            case InvitationJoinError.invalid:
                state = .invalid
            case InvitationJoinError.expired:
                state = .expired
            case is CancellationError:
                resetState()
            default:
                state = .failed
            }
        }

        if attemptID == attempt {
            attemptID = nil
        }
    }

    func takeAcceptedGroupID() -> UUID? {
        guard case .accepted(let groupID) = state else { return nil }
        resetState()
        return groupID
    }

    func discard() {
        if let pending = coordinator.pending {
            coordinator.discard(pending)
        }
        resetState()
    }

    private func resetState() {
        attemptID = nil
        if coordinator.pending == nil {
            state = .idle
        } else {
            state = signedInUserID == nil ? .waitingForSignIn : .ready
        }
    }
}
