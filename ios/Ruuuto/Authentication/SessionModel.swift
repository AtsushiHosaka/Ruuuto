import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class SessionModel {
    enum State: Equatable {
        case restoring
        case signedOut
        case signedIn(UUID)
    }

    private(set) var state: State = .restoring
    let client: SupabaseClient
    let profile: ProfileViewModel

    var userID: UUID? {
        guard case .signedIn(let userID) = state else { return nil }
        return userID
    }

    init(configuration: AppConfiguration) {
        let client = SupabaseClient(
            supabaseURL: configuration.supabaseURL,
            supabaseKey: configuration.publishableKey
        )
        self.client = client
        profile = ProfileViewModel {
            try await client.rpc("ruuuto_my_profile").execute().value
        }
    }

    func observe() async {
        for await (_, session) in client.auth.authStateChanges {
            if Task.isCancelled { return }
            if let session, !session.isExpired {
                updateState(.signedIn(session.user.id))
            } else {
                updateState(.signedOut)
            }
        }
    }

    func signIn(email: String, password: String) async throws {
        let session = try await client.auth.signIn(email: email, password: password)
        updateState(.signedIn(session.user.id))
    }

    func signUp(email: String, password: String) async throws -> Bool {
        let response = try await client.auth.signUp(email: email, password: password)
        if let session = response.session {
            updateState(.signedIn(session.user.id))
            return true
        }
        return false
    }

    func signOut() async throws {
        let previousState = state
        do {
            try await client.auth.signOut(scope: .local)
        } catch {
            // The SDK removes the local session before calling the logout endpoint.
            guard client.auth.currentSession == nil else { throw error }
        }

        if client.auth.currentSession == nil, state == previousState {
            updateState(.signedOut)
        }
    }

    private func updateState(_ newState: State) {
        state = newState
        profile.selectUser(userID)
    }
}
