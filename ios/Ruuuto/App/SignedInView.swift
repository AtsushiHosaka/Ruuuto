import SwiftUI

struct SignedInView: View {
    @State private var workspace: SignedInWorkspace
    @State private var signOutError = false

    init(session: SessionModel, userID: UUID) {
        _workspace = State(initialValue: SignedInWorkspace(session: session, userID: userID))
    }

    var body: some View {
        Group {
            if workspace.destination == .createGroup, let groupCreation = workspace.groupCreation {
                CreateGroupView(
                    viewModel: groupCreation,
                    creatorInitial: creatorInitial,
                    close: workspace.showGroups
                )
            } else {
                signedInHome
            }
        }
        .environment(workspace)
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

    private var signedInHome: some View {
        ContentView()
            .navigationTitle(Text(verbatim: "Ruuuto"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: workspace.showGroupCreation) {
                        Label {
                            Text("groups.create.action.open", tableName: "Groups")
                        } icon: {
                            Image(systemName: "plus")
                        }
                    }
                    .disabled(workspace.isSigningOut)
                }
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
    }

    private var creatorInitial: String? {
        guard case .loaded(let profile) = workspace.profile.state else { return nil }
        let name = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.first.map { String($0).uppercased() }
    }
}
