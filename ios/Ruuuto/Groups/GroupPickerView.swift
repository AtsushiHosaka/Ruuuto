import SwiftUI

struct BoardGroup: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
}

struct GroupPickerView: View {
    let groups: [BoardGroup]
    let selectedID: UUID?
    let select: (BoardGroup) -> Void
    var create: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if groups.isEmpty {
                    Text("参加中のグループはありません")
                        .foregroundStyle(RuuutoPalette.sub)
                        .padding(.vertical, 12)
                }

                ForEach(groups) { group in
                    groupRow(group)
                }

                if let create {
                    CreateGroupRow(action: create)
                }
            }
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

    private func groupRow(_ group: BoardGroup) -> some View {
        let isSelected = group.id == selectedID

        return Button {
            select(group)
        } label: {
            HStack(spacing: 14) {
                GroupTile(isSelected: isSelected)

                Text(group.name)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(RuuutoPalette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(RuuutoPalette.ink)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct CreateGroupRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .frame(width: 60, height: 60)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(RuuutoPalette.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    }
                    .accessibilityHidden(true)

                Text("新しいグループ")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(RuuutoPalette.sub)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct GroupTile: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(isSelected ? RuuutoPalette.accent : RuuutoPalette.ink)

            photoPaper(tint: RuuutoPalette.muted)
                .rotationEffect(.degrees(-8))
                .offset(x: -9, y: -5)

            photoPaper(tint: RuuutoPalette.accent)
                .rotationEffect(.degrees(6))
                .offset(x: 10, y: 6)
        }
        .frame(width: 60, height: 60)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 19)
                    .strokeBorder(RuuutoPalette.ink, lineWidth: 2)
                    .padding(-4)
            }
        }
        .accessibilityHidden(true)
    }

    private func photoPaper(tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(tint)
            .frame(width: 18, height: 18)
            .padding(2)
            .padding(.bottom, 4)
            .background(.white, in: RoundedRectangle(cornerRadius: 2))
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
    }
}
