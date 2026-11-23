#if DEBUG
import SwiftUI

/// Debug-only preview of group creation that never connects to Supabase.
///
/// Launch with `-RuuutoCreateGroupDemo success` or `-RuuutoCreateGroupDemo failFirst`.
/// `failFirst` fails the first request and succeeds on retry.
struct CreateGroupDemoView: View {
    static var mode: String? {
        UserDefaults.standard.string(forKey: "RuuutoCreateGroupDemo")
    }

    @State private var directory = GroupDirectoryViewModel(loadGroups: { [] })
    @State private var creation: CreateGroupViewModel?

    var body: some View {
        NavigationStack {
            if let creation {
                CreateGroupView(viewModel: creation, creatorInitial: "R", close: {})
            } else if let selectedID = directory.selectedID,
                      let group = directory.groups.first(where: { $0.id == selectedID }) {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(RuuutoPalette.accent)
                    Text(verbatim: "selectedID = created group")
                        .font(.caption.monospaced())
                        .foregroundStyle(RuuutoPalette.sub)
                    Text(verbatim: group.name)
                        .font(RuuutoType.rounded(.title))
                        .accessibilityIdentifier("createGroupDemo.selected")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RuuutoPalette.page.ignoresSafeArea())
                .navigationTitle(Text(verbatim: "Ruuuto"))
            }
        }
        .onAppear(perform: start)
    }

    private func start() {
        guard creation == nil, directory.selectedID == nil else { return }
        var remainingFailures = Self.mode == "failFirst" ? 1 : 0
        creation = CreateGroupViewModel(
            createGroup: { name, _ in
                try await Task.sleep(for: .seconds(1))
                if remainingFailures > 0 {
                    remainingFailures -= 1
                    throw URLError(.notConnectedToInternet)
                }
                return BoardGroup(id: UUID(), name: name)
            },
            selectGroup: { group in
                directory.selectGroup(group)
                creation = nil
            }
        )
    }
}
#endif
