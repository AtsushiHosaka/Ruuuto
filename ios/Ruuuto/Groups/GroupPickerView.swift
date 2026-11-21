import SwiftUI

struct BoardGroup: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
}

struct GroupPickerView: View {
    let groups: [BoardGroup]
    let selectedID: UUID?
    let select: (BoardGroup) -> Void

    var body: some View {
        List {
            if groups.isEmpty {
                Text("参加中のグループはありません")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(groups) { group in
                    Button {
                        select(group)
                    } label: {
                        HStack {
                            Text(group.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if group.id == selectedID {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.tint)
                                    .accessibilityHidden(true)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(group.id == selectedID ? .isSelected : [])
                }
            }
        }
        .navigationTitle("グループ")
        .navigationBarTitleDisplayMode(.inline)
    }
}
