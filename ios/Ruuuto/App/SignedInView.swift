import SwiftUI

struct SignedInView: View {
    @State private var workspace: SignedInWorkspace
    @State private var signOutError = false

    @Binding var pendingInvitation: InvitationLink?

    init(session: SessionModel, userID: UUID, invitationOrigin: URL?, pendingInvitation: Binding<InvitationLink?>) {
        _pendingInvitation = pendingInvitation
        _workspace = State(initialValue: SignedInWorkspace(
            session: session, userID: userID, invitationOrigin: invitationOrigin
        ))
    }

    var body: some View {
        @Bindable var workspace = workspace
        ContentView()
            .environment(workspace)
            .navigationTitle("Ruuuto")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("ログアウト") {
                        Task {
                            do {
                                try await workspace.signOut()
                            } catch {
                                signOutError = true
                            }
                        }
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
            .task(id: workspace.boardLoadRequestID) { [groupID = workspace.groups.selectedID] in
                await workspace.currentBoard.selectGroup(groupID)
            }
            .alert("ログアウトできませんでした", isPresented: $signOutError) {
                Button("閉じる", role: .cancel) {}
            } message: {
                Text("通信を確認して、もう一度お試しください。")
            }
    }
}
