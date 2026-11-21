import SwiftUI

struct GroupDirectoryView: View {
    let loadGroups: () async throws -> [BoardGroup]
    let selectedID: UUID?
    let select: (BoardGroup) -> Void
    var create: (() -> Void)? = nil

    @State private var groups: [BoardGroup]?
    @State private var failed = false
    @State private var retry = 0

    var body: some View {
        Group {
            if let groups {
                GroupPickerView(groups: groups, selectedID: selectedID, select: select, create: create)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if failed {
                            Label("グループを取得できませんでした", systemImage: "wifi.exclamationmark")
                                .font(.headline)
                            Button("再試行") { retry += 1 }
                                .buttonStyle(.bordered)
                        } else {
                            ProgressView("グループを読み込み中")
                                .tint(RuuutoPalette.ink)
                        }

                        if let create {
                            CreateGroupRow(action: create)
                        }
                    }
                    .foregroundStyle(RuuutoPalette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RuuutoPalette.page.ignoresSafeArea())
                .navigationTitle("グループ")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(RuuutoPalette.page, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(.light, for: .navigationBar)
            }
        }
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
