import SwiftUI

struct AuthenticationView: View {
    @State private var session: SessionModel?
    @State private var pendingInvitation: InvitationLink?
    private let invitationOrigin: URL?

    init(configuration: AppConfiguration? = AppConfiguration()) {
        _session = State(initialValue: configuration.map(SessionModel.init))
        invitationOrigin = configuration?.invitationOrigin
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
                    SignedInView(
                        session: session,
                        userID: userID,
                        invitationOrigin: invitationOrigin,
                        pendingInvitation: $pendingInvitation
                    )
                        .id(userID)
                }
            }
            .task { await session.observe() }
            .onOpenURL { url in
                guard let invitationOrigin,
                      let link = InvitationLink(url: url, allowedOrigin: invitationOrigin,
                                                pathPrefix: InvitationLink.pathPrefix) else { return }
                pendingInvitation = link
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
