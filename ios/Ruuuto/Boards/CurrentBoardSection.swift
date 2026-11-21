import SwiftUI

struct CurrentBoardSection: View {
    let group: BoardGroup
    let loadBoard: (UUID) async throws -> CurrentBoard
    var canEdit: (CurrentBoard) -> Bool = { _ in true }
    var edit: ((CurrentBoard) -> Void)? = nil

    @State private var state: CurrentBoardState = .idle
    @State private var loadedGroupID: UUID?
    @State private var reload = 0

    private struct Request: Hashable {
        let groupID: UUID
        let reload: Int
    }

    var body: some View {
        let request = Request(groupID: group.id, reload: reload)
        CurrentBoardView(
            groupName: group.name,
            state: loadedGroupID == group.id ? state : .loading,
            retry: { reload += 1 },
            canEdit: canEdit,
            edit: edit
        )
        .task(id: request) {
            guard !Task.isCancelled else { return }
            loadedGroupID = request.groupID
            state = .loading
            do {
                let board = try await loadBoard(request.groupID)
                guard !Task.isCancelled else { return }
                guard board.groupID == request.groupID else {
                    state = .failed("選んだグループのボードを表示できませんでした。")
                    return
                }
                state = .loaded(board)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed("お題を取得できませんでした。")
            }
        }
    }
}
