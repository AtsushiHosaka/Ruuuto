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
            Form {
                Section {
                    TextField("グループ名を入力", text: $name)
                        .textContentType(.organizationName)
                        .submitLabel(.done)
                        .disabled(isCreating)
                        .onSubmit(submit)
                } header: {
                    Text("グループ名")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(RuuutoPalette.sub)
                }
                .listRowBackground(Color.white)

                if let creationError {
                    Section {
                        Label(creationError, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                    .listRowBackground(Color.white)
                }
            }
            .scrollContentBackground(.hidden)
            .background(RuuutoPalette.page.ignoresSafeArea())
            .tint(RuuutoPalette.ink)
            .navigationTitle("グループを作成")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(RuuutoPalette.page, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .disabled(isCreating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isCreating {
                        ProgressView()
                            .accessibilityLabel("作成中")
                    } else {
                        Button("作成", action: submit)
                            .disabled(trimmedName.isEmpty)
                    }
                }
            }
        }
        .interactiveDismissDisabled(isCreating)
        .environment(\.colorScheme, .light)
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
