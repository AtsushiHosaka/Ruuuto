import Foundation
import Observation

@MainActor
@Observable
final class CreateGroupViewModel {
    enum State: Equatable {
        case idle
        case creating
        case failed(String)
        case created(BoardGroup)
    }

    var name = ""
    private(set) var state: State = .idle

    private let createGroup: @MainActor (String, UUID) async throws -> BoardGroup
    @ObservationIgnored private var lastRequest: (name: String, id: UUID)?
    private let selectGroup: @MainActor (BoardGroup) async -> Void

    init(
        createGroup: @escaping @MainActor (String, UUID) async throws -> BoardGroup,
        selectGroup: @escaping @MainActor (BoardGroup) async -> Void
    ) {
        self.createGroup = createGroup
        self.selectGroup = selectGroup
    }

    var isCreating: Bool { state == .creating }

    var creationError: String? {
        guard case .failed(let message) = state else { return nil }
        return message
    }

    var createdGroup: BoardGroup? {
        guard case .created(let group) = state else { return nil }
        return group
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
        let requestID = if let lastRequest, lastRequest.name == name {
            lastRequest.id
        } else {
            UUID()
        }
        lastRequest = (name, requestID)

        state = .creating

        do {
            let group = try await createGroup(name, requestID)
            state = .created(group)
            await selectGroup(group)
            return group
        } catch is CancellationError {
            state = .idle
            return nil
        } catch {
            state = .failed("グループを作成できませんでした。もう一度お試しください。")
            return nil
        }
    }
}
