import SwiftUI

struct AuthenticationView: View {
    let notifications: NotificationAppDelegate

    @State private var session: SessionModel?
    @State private var signOutError = false

    init(notifications: NotificationAppDelegate, configuration: AppConfiguration? = AppConfiguration()) {
        self.notifications = notifications
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
                case .signedIn:
                    ContentView()
                        .navigationTitle("ルート")
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                NavigationLink {
                                    NotificationSettingsView(notifications: notifications)
                                } label: {
                                    Label("通知", systemImage: "bell")
                                }
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("ログアウト") {
                                    Task {
                                        do {
                                            try await session.signOut()
                                        } catch {
                                            signOutError = true
                                        }
                                    }
                                }
                            }
                        }
                }
            }
            .task { await session.observe() }
            .alert("ログアウトできませんでした", isPresented: $signOutError) {
                Button("閉じる", role: .cancel) {}
            } message: {
                Text("通信を確認して、もう一度お試しください。")
            }
        } else {
            ContentUnavailableView(
                "接続設定がありません",
                systemImage: "gear",
                description: Text("開発チームに接続先を確認してください。")
            )
        }
    }
}
