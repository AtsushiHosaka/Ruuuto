import Foundation
import Observation

enum CurrentBoardState: Equatable, Sendable {
    case idle
    case loading
    case loaded(CurrentBoard)
    case failed(String)
}

@MainActor
@Observable
final class CurrentBoardViewModel {
    private(set) var selectedGroupID: UUID?
    private(set) var state: CurrentBoardState = .idle

    private let loadBoard: @MainActor (UUID) async throws -> CurrentBoard
    @ObservationIgnored private var activeRequestID: UUID?

    init(loadBoard: @escaping @MainActor (UUID) async throws -> CurrentBoard) {
        self.loadBoard = loadBoard
    }

    func state(for groupID: UUID) -> CurrentBoardState {
        selectedGroupID == groupID ? state : .loading
    }

    func selectGroup(_ groupID: UUID?) async {
        guard !Task.isCancelled else { return }

        selectedGroupID = groupID
        guard groupID != nil else {
            activeRequestID = nil
            state = .idle
            return
        }

        await reload()
    }

    func reload() async {
        guard let groupID = selectedGroupID, !Task.isCancelled else { return }

        let requestID = UUID()
        activeRequestID = requestID
        state = .loading

        let result: CurrentBoardState
        do {
            let board = try await loadBoard(groupID)
            if board.groupID == groupID {
                result = .loaded(board)
            } else {
                result = .failed(String(localized: "boards.current.group_mismatch"))
            }
        } catch is CancellationError {
            result = .idle
        } catch {
            result = .failed(String(localized: "boards.current.load_failed"))
        }

        guard activeRequestID == requestID else { return }
        activeRequestID = nil
        state = Task.isCancelled ? .idle : result
    }

    // A completed mutation may refresh its own group without changing the selection.
    func reload(for groupID: UUID) async {
        guard selectedGroupID == groupID else { return }
        await reload()
    }
}
