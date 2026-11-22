import SwiftUI

struct SignedInView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var workspace: SignedInWorkspace
    @State private var signOutError = false

    @Binding var pendingInvitation: InvitationLink?

    init(
        session: SessionModel,
        userID: UUID,
        invitationOrigin: URL?,
        pendingInvitation: Binding<InvitationLink?>,
        notificationDelegate: NotificationAppDelegate
    ) {
        _pendingInvitation = pendingInvitation
        _workspace = State(initialValue: SignedInWorkspace(
            session: session,
            userID: userID,
            invitationOrigin: invitationOrigin,
            notificationDelegate: notificationDelegate
        ))
    }

    var body: some View {
        @Bindable var workspace = workspace
        ContentView()
            .environment(workspace)
            .navigationTitle(Text(verbatim: "Ruuuto"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            do {
                                try await workspace.signOut()
                            } catch {
                                signOutError = true
                            }
                        }
                    } label: {
                        Text("auth.action.sign_out", tableName: "Authentication")
                    }
                    .disabled(workspace.isSigningOut)
                }
            }
            .onChange(of: pendingInvitation, initial: true) {
                guard let pendingInvitation else { return }
                workspace.receiveInvitation(pendingInvitation.url)
                self.pendingInvitation = nil
            }
            .sheet(item: $workspace.sharedInvitation) { invitation in
                SystemShareSheet(url: invitation.url)
            }
            .task { await workspace.start() }
            .task(id: scenePhase == .active ? workspace.notifications.pendingTap?.id : nil) {
                guard scenePhase == .active else { return }
                await workspace.openPendingNotification()
            }
            .task(id: workspace.boardLoadRequestID) { [groupID = workspace.groups.selectedID] in
                await workspace.loadSelectedBoard(groupID)
            }
            .alert(Text("auth.sign_out.failure.title", tableName: "Authentication"), isPresented: $signOutError) {
                Button(role: .cancel) {} label: {
                    Text("auth.action.close", tableName: "Authentication")
                }
            } message: {
                Text("auth.sign_out.failure.retry", tableName: "Authentication")
            }
    }
}
