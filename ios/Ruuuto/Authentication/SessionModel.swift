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

    init(configuration: AppConfiguration) {
        client = SupabaseClient(
            supabaseURL: configuration.supabaseURL,
            supabaseKey: configuration.publishableKey
        )
    }

    func observe() async {
        for await (_, session) in client.auth.authStateChanges {
            if Task.isCancelled { return }
            if let session, !session.isExpired {
                state = .signedIn(session.user.id)
            } else {
                state = .signedOut
            }
        }
    }

    func signIn(email: String, password: String) async throws {
        let session = try await client.auth.signIn(email: email, password: password)
        state = .signedIn(session.user.id)
    }

    func signUp(email: String, password: String) async throws -> Bool {
        let response = try await client.auth.signUp(email: email, password: password)
        if let session = response.session {
            state = .signedIn(session.user.id)
            return true
        }
        return false
    }

    func signOut() async throws {
        try await client.auth.signOut(scope: .local)
        state = .signedOut
    }
}
