import SwiftUI

struct EditTopicView: View {
    let groupName: String
    let board: CurrentBoard
    let save: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var editingTopic: Bool
    @State private var topic: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(groupName: String, board: CurrentBoard, save: @escaping (String) async throws -> Void) {
        self.groupName = groupName
        self.board = board
        self.save = save
        _topic = State(initialValue: board.topic)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    boardContext
                        .padding(.bottom, 24)

                    Text("お題")
                        .font(RuuutoType.rounded(.footnote).weight(.bold))
                        .foregroundStyle(RuuutoPalette.line)
                        .accessibilityHidden(true)

                    TextField("お題", text: $topic, axis: .vertical)
                        .font(RuuutoType.rounded(.title).weight(.heavy))
                        .foregroundStyle(.white)
                        .focused($editingTopic)
                        .disabled(isSaving)
                        .frame(minHeight: 104, alignment: .topLeading)
                        .padding(.top, 7)
                        .padding(.bottom, 4)

                    Rectangle()
                        .fill(editingTopic ? RuuutoPalette.accent : RuuutoPalette.line.opacity(0.52))
                        .frame(height: 1)
                        .accessibilityHidden(true)

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle")
                            .font(RuuutoType.body(.footnote))
                            .foregroundStyle(RuuutoPalette.line)
                            .padding(.top, 18)
                    }

                    if isSaving {
                        ProgressView("保存中")
                            .font(RuuutoType.body(.footnote))
                            .padding(.top, 18)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
                .foregroundStyle(.white)
            }
            .background {
                ZStack {
                    RuuutoPalette.ink
                    Canvas { context, size in
                        var dots = Path()
                        for y in stride(from: 9.0, to: size.height, by: 18.0) {
                            for x in stride(from: 9.0, to: size.width, by: 18.0) {
                                dots.addEllipse(in: CGRect(x: x, y: y, width: 2, height: 2))
                            }
                        }
                        context.fill(dots, with: .color(RuuutoPalette.soft))
                    }
                    .accessibilityHidden(true)
                }
                .ignoresSafeArea()
            }
            .scrollDismissesKeyboard(.interactively)
            .tint(RuuutoPalette.line)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("お題を変更")
                        .font(RuuutoType.rounded(.title3).weight(.heavy))
                        .foregroundStyle(.white)
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
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: submit)
                        .font(RuuutoType.rounded(.subheadline).weight(.heavy))
                        .disabled(isSaving || trimmedTopic.isEmpty || trimmedTopic == board.topic)
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .environment(\.colorScheme, .dark)
    }

    private var boardContext: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(groupName)
                    .font(RuuutoType.rounded(.subheadline).weight(.heavy))

                Spacer(minLength: 0)

                Label(
                    board.closesAt.formatted(.dateTime.month(.defaultDigits).day()),
                    systemImage: "clock"
                )
                .font(RuuutoType.body(.footnote))
                .foregroundStyle(RuuutoPalette.line)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("締切 \(board.closesAt.formatted(date: .abbreviated, time: .shortened))")
            }

            Rectangle()
                .fill(RuuutoPalette.soft)
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }

    private var trimmedTopic: String {
        topic.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        let submittedTopic = trimmedTopic
        guard !isSaving, !submittedTopic.isEmpty, submittedTopic != board.topic else { return }
        isSaving = true
        errorMessage = nil

        Task {
            defer { isSaving = false }
            do {
                try await save(submittedTopic)
                dismiss()
            } catch is CancellationError {
                return
            } catch {
                errorMessage = (error as? any LocalizedError)?.errorDescription
                    ?? "お題を保存できませんでした。もう一度お試しください。"
            }
        }
    }
}
