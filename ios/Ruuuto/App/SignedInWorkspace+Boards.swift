import Foundation

extension SignedInWorkspace {
    func showGroupCreation() {
        guard isCurrentSession else { return }
        let creationID = UUID()
        let client = session.client
        let model = CreateGroupViewModel(
            createGroup: { try await CreateGroupAPI.create(client: client, name: $0) },
            selectGroup: { [weak self] group in
                guard let self, self.isCurrentSession,
                      case .createGroup(creationID, _) = self.destination else { return }
                self.groups.selectGroup(group)
                self.openBoard(groupID: group.id)
            }
        )
        navigate(to: .createGroup(id: creationID, model: model))
    }

    func showTopicEditor() {
        guard isCurrentSession,
              case let .board(groupID) = destination,
              case let .loaded(board) = currentBoard.state(for: groupID) else { return }

        let client = session.client
        let editor = TopicEditorViewModel(
            board: board,
            saveTopic: { try await TopicEditorAPI.save(client: client, boardID: $0, topic: $1) },
            reloadBoard: { [weak self] id in
                guard let self, self.isCurrentSession else { return }
                await self.currentBoard.reload(for: id)
            }
        )
        navigate(to: .editTopic(editor))
    }

    func saveTopic() async {
        guard isCurrentSession, let editor = topicEditor else { return }
        guard await editor.saveChanges(), isCurrentSession, !Task.isCancelled,
              topicEditor === editor else { return }
        closeTopicEditor()
    }

    func closeTopicEditor() {
        guard let editor = topicEditor else { return }
        openBoard(groupID: editor.board.groupID)
    }
}
