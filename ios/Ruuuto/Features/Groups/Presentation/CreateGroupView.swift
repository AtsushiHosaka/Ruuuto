import SwiftUI

struct CreateGroupView: View {
    @Bindable var viewModel: CreateGroupViewModel
    /// The first letter of the creator's display name, shown in the list preview.
    let creatorInitial: String?
    let close: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    nameField
                    preview
                        .padding(.top, 28)
                    feedback
                }
                .frame(maxWidth: 480, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(RuuutoPalette.ink)
        .background(RuuutoPalette.page.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .onAppear { isNameFocused = true }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button(action: close) {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("groups.create.action.back", tableName: "Groups"))

            Text("groups.create.title", tableName: "Groups")
                .font(RuuutoType.rounded(.title3))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)

            Button {
                submit()
            } label: {
                Group {
                    if viewModel.isCreating {
                        ProgressView()
                            .tint(RuuutoPalette.sub)
                            .accessibilityLabel(Text("groups.create.in_progress", tableName: "Groups"))
                    } else {
                        Text("groups.create.action.create", tableName: "Groups")
                            .font(RuuutoType.rounded(.callout))
                            .foregroundStyle(viewModel.canSubmit ? RuuutoPalette.ink : RuuutoPalette.sub.opacity(0.65))
                    }
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSubmit)
            .accessibilityIdentifier("createGroup.submit")
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("groups.create.name.label", tableName: "Groups")
                .font(RuuutoType.rounded(.footnote))
                .foregroundStyle(RuuutoPalette.sub)
                .accessibilityHidden(true)

            TextField(
                text: $viewModel.name,
                prompt: Text("groups.create.name.placeholder", tableName: "Groups")
                    .foregroundStyle(RuuutoPalette.sub.opacity(0.8))
            ) {
                Text("groups.create.name.label", tableName: "Groups")
            }
            .font(RuuutoType.rounded(.title2))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($isNameFocused)
            .disabled(viewModel.isCreating)
            .onSubmit(submit)
            .padding(.vertical, 10)
            .frame(minHeight: 58)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(RuuutoPalette.line)
                    .frame(height: 1)
            }
            .accessibilityIdentifier("createGroup.name")
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("groups.create.preview.caption", tableName: "Groups")
                .font(RuuutoType.rounded(.caption))
                .foregroundStyle(RuuutoPalette.sub)

            HStack(spacing: 14) {
                GroupTile()
                VStack(alignment: .leading, spacing: 4) {
                    previewTitle
                        .font(RuuutoType.rounded(.headline))
                        .fixedSize(horizontal: false, vertical: true)
                    creatorAvatar
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 64)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Line()
                .stroke(RuuutoPalette.line, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("createGroup.preview")
    }

    @ViewBuilder
    private var previewTitle: some View {
        if let name = viewModel.previewName {
            Text(verbatim: name)
        } else {
            Text("groups.create.name.placeholder", tableName: "Groups")
                .foregroundStyle(RuuutoPalette.sub)
        }
    }

    private var creatorAvatar: some View {
        Group {
            if let creatorInitial {
                Text(verbatim: creatorInitial)
                    .font(.system(size: 10, weight: .bold))
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 10, weight: .bold))
            }
        }
        .frame(width: 24, height: 24)
        .background(RuuutoPalette.line.opacity(0.45), in: Circle())
        .overlay(Circle().stroke(RuuutoPalette.page, lineWidth: 2))
        .accessibilityElement()
        .accessibilityLabel(Text("groups.create.preview.creator", tableName: "Groups"))
    }

    @ViewBuilder
    private var feedback: some View {
        if let message = viewModel.creationError {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: message)
                    .font(RuuutoType.body(.footnote, dynamicTypeSize: dynamicTypeSize))
                    .foregroundStyle(RuuutoPalette.sub)
                    .padding(.top, 18)
                    .accessibilityIdentifier("createGroup.error")

                Button {
                    submit()
                } label: {
                    Label {
                        Text("groups.create.action.retry", tableName: "Groups")
                    } icon: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .font(RuuutoType.rounded(.callout))
                    .foregroundStyle(viewModel.canSubmit ? RuuutoPalette.ink : RuuutoPalette.sub)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        viewModel.canSubmit ? RuuutoPalette.accent : RuuutoPalette.line.opacity(0.45),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canSubmit)
                .padding(.top, 22)
                .accessibilityIdentifier("createGroup.retry")
            }
        }
    }

    private func submit() {
        guard viewModel.canSubmit else { return }
        isNameFocused = false
        Task { await viewModel.submit() }
    }
}

/// The tile used for a group in the group list, with two small photos.
private struct GroupTile: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(RuuutoPalette.ink)
            .frame(width: 60, height: 60)
            .overlay(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    MiniPhoto(fill: RuuutoPalette.line)
                        .rotationEffect(.degrees(-8))
                        .offset(x: 8, y: 10)
                    MiniPhoto(fill: RuuutoPalette.accent.opacity(0.7))
                        .rotationEffect(.degrees(6))
                        .offset(x: 28, y: 20)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityHidden(true)
    }
}

private struct MiniPhoto: View {
    let fill: Color

    var body: some View {
        Rectangle()
            .fill(fill)
            .padding(EdgeInsets(top: 2, leading: 2, bottom: 6, trailing: 2))
            .frame(width: 24, height: 28)
            .background(.white, in: RoundedRectangle(cornerRadius: 2))
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

#Preview("空") {
    CreateGroupView(
        viewModel: CreateGroupViewModel(createGroup: { name, _ in BoardGroup(id: UUID(), name: name) }, selectGroup: { _ in }),
        creatorInitial: "R",
        close: {}
    )
}

#Preview("失敗") {
    let viewModel = CreateGroupViewModel(
        createGroup: { _, _ in throw URLError(.notConnectedToInternet) },
        selectGroup: { _ in }
    )
    viewModel.name = "テスト班"
    return CreateGroupView(viewModel: viewModel, creatorInitial: "R", close: {})
        .task { await viewModel.submit() }
}
