import SwiftUI

struct CreateGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isCreating = false
    @State private var creationError: String?

    let create: @MainActor (String) async throws -> Void

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("グループ名")
                        .font(RuuutoType.rounded(.footnote).weight(.bold))
                        .foregroundStyle(RuuutoPalette.sub)
                        .accessibilityHidden(true)

                    TextField(
                        "グループ名",
                        text: $name,
                        prompt: Text("新しいグループ")
                            .font(RuuutoType.rounded(.title3).weight(.medium))
                            .foregroundStyle(RuuutoPalette.sub)
                    )
                    .font(RuuutoType.rounded(.title2).weight(.heavy))
                    .textContentType(.organizationName)
                    .submitLabel(.done)
                    .disabled(isCreating)
                    .onSubmit(submit)
                    .frame(minHeight: 58)

                    Rectangle()
                        .fill(RuuutoPalette.line)
                        .frame(height: 1)
                        .accessibilityHidden(true)

                    preview
                        .padding(.top, 28)

                    if let creationError {
                        Label(creationError, systemImage: "exclamationmark.circle")
                            .font(RuuutoType.body(.footnote))
                            .foregroundStyle(.red)
                            .padding(.top, 18)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
                .foregroundStyle(RuuutoPalette.ink)
            }
            .background(RuuutoPalette.page.ignoresSafeArea())
            .tint(RuuutoPalette.ink)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(RuuutoPalette.page, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("グループ作成")
                        .font(RuuutoType.rounded(.title3).weight(.heavy))
                        .accessibilityAddTraits(.isHeader)
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("戻る")
                    .disabled(isCreating)
                }

                ToolbarItem(placement: .confirmationAction) {
                    if isCreating {
                        ProgressView()
                            .accessibilityLabel("作成中")
                    } else {
                        Button("作成", action: submit)
                            .font(RuuutoType.rounded(.subheadline).weight(.heavy))
                            .disabled(trimmedName.isEmpty)
                    }
                }
            }
        }
        .interactiveDismissDisabled(isCreating)
        .environment(\.colorScheme, .light)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Canvas { context, size in
                let rule = Path { path in
                    path.move(to: CGPoint(x: 0, y: size.height / 2))
                    path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                }
                context.stroke(rule, with: .color(RuuutoPalette.line), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .frame(height: 1)
            .accessibilityHidden(true)

            Text("一覧での表示")
                .font(RuuutoType.rounded(.caption).weight(.bold))
                .foregroundStyle(RuuutoPalette.sub)

            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(RuuutoPalette.ink)

                    photo(RuuutoPalette.accent)
                        .rotationEffect(.degrees(-8))
                        .offset(x: -10, y: -6)
                    photo(RuuutoPalette.line)
                        .rotationEffect(.degrees(6))
                        .offset(x: 10, y: 4)
                }
                .frame(width: 60, height: 60)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(trimmedName.isEmpty ? "新しいグループ" : trimmedName)
                        .font(RuuutoType.rounded(.headline).weight(trimmedName.isEmpty ? .medium : .heavy))
                        .foregroundStyle(trimmedName.isEmpty ? RuuutoPalette.sub : RuuutoPalette.ink)

                    Text("R")
                        .font(RuuutoType.body(.caption2).weight(.bold))
                        .foregroundStyle(RuuutoPalette.ink)
                        .frame(width: 24, height: 24)
                        .background(RuuutoPalette.line.opacity(0.4), in: Circle())
                        .accessibilityLabel("作成者1人")
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func photo(_ tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(tint)
            .frame(width: 20, height: 20)
            .padding(.horizontal, 2)
            .padding(.top, 2)
            .padding(.bottom, 6)
            .background(.white, in: RoundedRectangle(cornerRadius: 2))
    }

    private func submit() {
        let submittedName = trimmedName
        guard !submittedName.isEmpty, !isCreating else { return }
        isCreating = true
        creationError = nil

        Task {
            defer { isCreating = false }
            do {
                try await create(submittedName)
                dismiss()
            } catch is CancellationError {
                return
            } catch {
                creationError = "グループを作成できませんでした。もう一度お試しください。"
            }
        }
    }
}
