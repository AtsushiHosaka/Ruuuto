import SwiftUI

struct GroupManagementView: View {
    let loadGroups: () async throws -> [BoardGroup]
    let selectedID: UUID?
    let select: (BoardGroup) -> Void
    let createGroup: (String) async throws -> BoardGroup

    @State private var creating = false
    @State private var revision = 0

    var body: some View {
        GroupDirectoryView(loadGroups: loadGroups, selectedID: selectedID, select: select)
            .id(revision)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("グループを作成", systemImage: "plus") {
                        creating = true
                    }
                }
            }
            .sheet(isPresented: $creating) {
                CreateGroupView { name in
                    let group = try await createGroup(name)
                    select(group)
                    revision += 1
                }
            }
    }
}
