import Foundation
import Observation

enum TopicSaveError: Error, Equatable, Sendable {
    case forbidden
    case invalidTopic
    case closedBoard
}

@MainActor
@Observable
final class TopicEditorViewModel {
    enum State: Equatable {
        case editing
        case saving
        case saved
        case failed(String)
    }

    let board: CurrentBoard
    var topic: String
    private(set) var state: State = .editing

    private let saveTopic: @MainActor (UUID, String) async throws -> Void
    private let reloadBoard: @MainActor (UUID) async -> Void

    init(
        board: CurrentBoard,
        saveTopic: @escaping @MainActor (UUID, String) async throws -> Void,
        reloadBoard: @escaping @MainActor (UUID) async -> Void
    ) {
        self.board = board
        self.topic = board.topic
        self.saveTopic = saveTopic
        self.reloadBoard = reloadBoard
    }

    var canSave: Bool { canSave(trimmedTopic) }

    var isSaving: Bool { state == .saving }

    var errorMessage: String? {
        guard case let .failed(message) = state else { return nil }
        return message
    }

    @discardableResult
    func saveChanges() async -> Bool {
        let submittedTopic = trimmedTopic
        guard canSave(submittedTopic), !Task.isCancelled else { return false }

        state = .saving
        do {
            try await saveTopic(board.id, submittedTopic)
        } catch is CancellationError {
            state = .editing
            return false
        } catch {
            state = .failed(message(for: error))
            return false
        }

        state = .saved
        await reloadBoard(board.groupID)
        return true
    }

    private var trimmedTopic: String {
        topic.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func canSave(_ submittedTopic: String) -> Bool {
        state != .saving && state != .saved && !submittedTopic.isEmpty && submittedTopic != board.topic
    }

    private func message(for error: Error) -> String {
        switch error as? TopicSaveError {
        case .forbidden:
            "このお題を変更する権限がありません。"
        case .invalidTopic:
            "お題の入力内容を確認してください。"
        case .closedBoard:
            "締切を過ぎたため、お題を変更できません。"
        case nil:
            "お題を保存できませんでした。もう一度お試しください。"
        }
    }
}
