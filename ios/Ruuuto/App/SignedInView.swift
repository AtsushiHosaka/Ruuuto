import SwiftUI

struct SignedInView: View {
    @State private var workspace: SignedInWorkspace
    @State private var signOutError = false

    init(session: SessionModel, userID: UUID) {
        _workspace = State(initialValue: SignedInWorkspace(session: session, userID: userID))
    }

    var body: some View {
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
            .task { await workspace.start() }
            .task(id: workspace.boardLoadRequestID) { [groupID = workspace.groups.selectedID] in
                await workspace.currentBoard.selectGroup(groupID)
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
