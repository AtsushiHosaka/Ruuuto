import SwiftUI

struct EditTopicView: View {
    let board: CurrentBoard
    let save: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var topic: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(board: CurrentBoard, save: @escaping (String) async throws -> Void) {
        self.board = board
        self.save = save
        _topic = State(initialValue: board.topic)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("お題", text: $topic, axis: .vertical)
                        .disabled(isSaving)
                } header: {
                    Text("お題")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(RuuutoPalette.sub)
                }
                .listRowBackground(Color.white)

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                        .listRowBackground(Color.white)
                }

                if isSaving {
                    ProgressView("保存中")
                        .listRowBackground(Color.white)
                }
            }
            .scrollContentBackground(.hidden)
            .background(RuuutoPalette.page.ignoresSafeArea())
            .tint(RuuutoPalette.ink)
            .navigationTitle("お題を変更")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(RuuutoPalette.page, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: submit)
                        .disabled(isSaving || trimmedTopic.isEmpty || trimmedTopic == board.topic)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
        .environment(\.colorScheme, .light)
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
