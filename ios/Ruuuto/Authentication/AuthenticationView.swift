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
                    ProgressView("ログイン状態を確認中")
                case .signedOut:
                    LoginView(signIn: session.signIn, signUp: session.signUp)
                case .signedIn(let userID):
                    SignedInView(session: session, userID: userID)
                        .id(userID)
                }
            }
            .task { await session.observe() }
        } else {
            ContentUnavailableView(
                "接続設定がありません",
                systemImage: "gear",
                description: Text("開発チームに接続先を確認してください。")
            )
        }
    }
}
