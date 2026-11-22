import SwiftUI

struct AuthenticationView: View {
    @State private var session: SessionModel?
    @State private var signOutError = false

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
                case .signedIn:
                    ContentView()
                        .navigationTitle(Text(verbatim: "Ruuuto"))
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    Task {
                                        do {
                                            try await session.signOut()
                                        } catch {
                                            signOutError = true
                                        }
                                    }
                                } label: {
                                    Text("auth.action.sign_out", tableName: "Authentication")
                                }
                            }
                        }
                }
            }
            .task { await session.observe() }
            .task(id: session.userID) { await session.profile.refresh() }
            .alert(
                Text("auth.sign_out.failure.title", tableName: "Authentication"),
                isPresented: $signOutError
            ) {
                Button(role: .cancel) {} label: {
                    Text("auth.action.close", tableName: "Authentication")
                }
            } message: {
                Text("auth.sign_out.failure.retry", tableName: "Authentication")
            }
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
