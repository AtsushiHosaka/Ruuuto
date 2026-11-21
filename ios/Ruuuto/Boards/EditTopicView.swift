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
                TextField("お題", text: $topic, axis: .vertical)
                    .disabled(isSaving)

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }

                if isSaving {
                    ProgressView("保存中")
                }
            }
            .navigationTitle("お題を変更")
            .navigationBarTitleDisplayMode(.inline)
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
