import SwiftUI

struct GroupDirectoryView: View {
    let loadGroups: () async throws -> [BoardGroup]
    let selectedID: UUID?
    let select: (BoardGroup) -> Void

    @State private var groups: [BoardGroup]?
    @State private var failed = false
    @State private var retry = 0

    var body: some View {
        Group {
            if let groups {
                GroupPickerView(groups: groups, selectedID: selectedID, select: select)
            } else if failed {
                ContentUnavailableView {
                    Label("グループを取得できませんでした", systemImage: "wifi.exclamationmark")
                } actions: {
                    Button("再試行") { retry += 1 }
                }
            } else {
                ProgressView("グループを読み込み中")
            }
        }
        .navigationTitle("グループ")
        .task(id: retry) {
            failed = false
            do {
                let result = try await loadGroups()
                guard !Task.isCancelled else { return }
                groups = result
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                failed = true
            }
        }
    }
}
