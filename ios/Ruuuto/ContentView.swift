import SwiftUI

struct ContentView: View {
    @Environment(SignedInWorkspace.self) private var workspace

    var body: some View {
        switch workspace.destination {
        case .groups:
            GroupSelectionView()
        case .createGroup:
            GroupSelectionView()
        case .board(let groupID, _):
            CurrentBoardScreen(groupID: groupID)
        }
    }
}

private struct GroupSelectionView: View {
    @Environment(SignedInWorkspace.self) private var workspace

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("boards.groups.title")
                .font(RuuutoType.rounded(.largeTitle))
                .foregroundStyle(RuuutoPalette.ink)

            switch workspace.groups.loadState {
            case .idle, .loading:
                ProgressView("boards.groups.loading")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed:
                VStack(spacing: 14) {
                    Text("boards.groups.load_failed")
                    Button("boards.current.retry") {
                        Task { await workspace.groups.refresh() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(RuuutoPalette.accent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded where workspace.groups.groups.isEmpty:
                Text("boards.groups.empty")
                    .foregroundStyle(RuuutoPalette.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(workspace.groups.groups) { group in
                            Button {
                                workspace.selectGroup(group.id)
                            } label: {
                                HStack {
                                    Image(systemName: "person.3.fill")
                                        .foregroundStyle(RuuutoPalette.accent)
                                    Text(verbatim: group.name)
                                        .font(RuuutoType.rounded(.headline))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(RuuutoPalette.muted)
                                }
                                .foregroundStyle(RuuutoPalette.ink)
                                .padding(16)
                                .background(.white.opacity(0.9))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .refreshable { await workspace.groups.refresh() }
            }
        }
        .padding(20)
        .background(RuuutoPalette.page.ignoresSafeArea())
    }
}
