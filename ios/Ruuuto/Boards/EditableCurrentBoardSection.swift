import SwiftUI

struct EditableCurrentBoardSection: View {
    let group: BoardGroup
    let loadBoard: (UUID) async throws -> CurrentBoard
    let canEdit: (CurrentBoard) -> Bool
    let saveTopic: (UUID, String) async throws -> Void

    @State private var editingBoard: CurrentBoard?
    @State private var revision = 0

    var body: some View {
        CurrentBoardSection(group: group, loadBoard: loadBoard, canEdit: canEdit, edit: openEditor)
            .id(revision)
            .sheet(item: $editingBoard) { board in
                EditTopicView(groupName: group.name, board: board) { topic in
                    try await saveTopic(board.id, topic)
                    revision += 1
                }
            }
            .onChange(of: group.id) {
                editingBoard = nil
            }
    }

    private func openEditor(_ board: CurrentBoard) {
        guard board.groupID == group.id, canEdit(board) else { return }
        editingBoard = board
    }
}
