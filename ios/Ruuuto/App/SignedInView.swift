import SwiftUI

struct SignedInView: View {
    @State private var workspace: SignedInWorkspace
    @State private var signOutError = false
    @State private var photoPost: PhotoPostViewModel?

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
            // ホーム画面ができるまでの仮の入口（RCNO-13）。開催中のボードがあるときだけ表示する。
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    if case .loaded(let board) = workspace.currentBoard.state {
                        Button {
                            photoPost = workspace.makePhotoPost(boardID: board.id)
                        } label: {
                            Label {
                                Text("photos.post.entry", tableName: "Photos")
                            } icon: {
                                Image(systemName: "photo.on.rectangle")
                            }
                        }
                    }
                }
            }
            .sheet(item: $photoPost) { PhotoPostView(model: $0) }
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
