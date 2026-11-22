import SwiftUI

struct AuthenticationView: View {
    @State private var session: SessionModel?

    init(configuration: AppConfiguration? = AppConfiguration()) {
        _session = State(initialValue: configuration.map(SessionModel.init))
    }

    var body: some View {
        if let session {
            NavigationStack {
                switch session.state {
                case .restoring:
                    ProgressView {
                        Text("auth.session.restoring", tableName: "Authentication")
                    }
                case .signedOut:
                    LoginView(signIn: session.signIn, signUp: session.signUp)
                case .signedIn(let userID):
                    SignedInView(session: session, userID: userID)
                        .id(userID)
                }
            }
            .task { await session.observe() }
            .task(id: session.userID) { await session.profile.refresh() }
        } else {
            ContentUnavailableView {
                Label {
                    Text("auth.configuration.missing.title", tableName: "Authentication")
                } icon: {
                    Image(systemName: "gear")
                }
            } description: {
                Text("auth.configuration.missing.help", tableName: "Authentication")
            }
        }
    }
}
