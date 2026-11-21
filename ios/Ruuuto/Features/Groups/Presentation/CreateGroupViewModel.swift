import Foundation
import Observation

@MainActor
@Observable
final class CreateGroupViewModel {
    var name = ""
    private(set) var isCreating = false
    private(set) var creationError: String?
    private(set) var createdGroup: BoardGroup?

    private let createGroup: @MainActor (String) async throws -> BoardGroup
    private let selectGroup: @MainActor (BoardGroup) async -> Void

    init(
        createGroup: @escaping @MainActor (String) async throws -> BoardGroup,
        selectGroup: @escaping @MainActor (BoardGroup) async -> Void
    ) {
        self.createGroup = createGroup
        self.selectGroup = selectGroup
    }

    var previewName: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var canSubmit: Bool {
        previewName != nil && !isCreating && createdGroup == nil
    }

    @discardableResult
    func submit() async -> BoardGroup? {
        guard !Task.isCancelled, !isCreating, createdGroup == nil, let name = previewName else { return nil }
        isCreating = true
        creationError = nil
        defer { isCreating = false }

        do {
            let group = try await createGroup(name)
            createdGroup = group
            await selectGroup(group)
            return group
        } catch is CancellationError {
            return nil
        } catch {
            creationError = "グループを作成できませんでした。もう一度お試しください。"
            return nil
        }
    }
}
