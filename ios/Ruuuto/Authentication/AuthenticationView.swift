import SwiftUI

struct AuthenticationView: View {
    @State private var session: SessionModel?
    @State private var pendingInvitation: InvitationLink?
    private let invitationOrigin: URL?
    private let notificationDelegate: NotificationAppDelegate

    init(notificationDelegate: NotificationAppDelegate, configuration: AppConfiguration? = AppConfiguration()) {
        self.notificationDelegate = notificationDelegate
        _session = State(initialValue: configuration.map(SessionModel.init))
        invitationOrigin = configuration?.invitationOrigin
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
                    SignedInView(
                        session: session,
                        userID: userID,
                        invitationOrigin: invitationOrigin,
                        pendingInvitation: $pendingInvitation,
                        notificationDelegate: notificationDelegate
                    )
                        .id(userID)
                }
            }
            .task { await session.observe() }
            .onChange(of: session.state) {
                if case .signedOut = session.state {
                    notificationDelegate.pauseRemoteDelivery()
                }
            }
            .onOpenURL { url in
                guard let invitationOrigin,
                      let link = InvitationLink(url: url, allowedOrigin: invitationOrigin,
                                                pathPrefix: InvitationLink.pathPrefix) else { return }
                pendingInvitation = link
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
