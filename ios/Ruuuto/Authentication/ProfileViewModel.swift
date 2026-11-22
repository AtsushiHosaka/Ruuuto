import Foundation
import Observation

@MainActor
@Observable
final class ProfileViewModel {
    enum State: Equatable {
        case idle
        case loading
        case loaded(ParticipantProfile)
        case failed
    }

    private let fetchProfile: @MainActor () async throws -> ParticipantProfile
    @ObservationIgnored private var userID: UUID?
    @ObservationIgnored private var requestID: UUID?
    private(set) var state: State = .idle

    init(fetchProfile: @escaping @MainActor () async throws -> ParticipantProfile) {
        self.fetchProfile = fetchProfile
    }

    func selectUser(_ userID: UUID?) {
        guard self.userID != userID else { return }
        self.userID = userID
        requestID = nil
        state = .idle
    }

    func refresh() async {
        guard let userID, !Task.isCancelled, requestID == nil else { return }
        let requestID = UUID()
        self.requestID = requestID
        let previousState = state
        state = .loading

        do {
            let profile = try await fetchProfile()
            guard self.requestID == requestID else { return }
            state = if Task.isCancelled {
                previousState
            } else if profile.id == userID {
                .loaded(profile)
            } else {
                .failed
            }
        } catch {
            guard self.requestID == requestID else { return }
            state = Task.isCancelled || error is CancellationError ? previousState : .failed
        }
        self.requestID = nil
    }
}
