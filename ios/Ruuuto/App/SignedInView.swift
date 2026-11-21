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
