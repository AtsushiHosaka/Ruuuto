import SwiftUI

struct CurrentBoardView: View {
    let groupName: String
    let state: CurrentBoardState
    let retry: () -> Void
    let canEdit: (CurrentBoard) -> Bool
    let edit: ((CurrentBoard) -> Void)?

    init(
        groupName: String,
        state: CurrentBoardState,
        retry: @escaping () -> Void,
        canEdit: @escaping (CurrentBoard) -> Bool = { _ in true },
        edit: ((CurrentBoard) -> Void)? = nil
    ) {
        self.groupName = groupName
        self.state = state
        self.retry = retry
        self.canEdit = canEdit
        self.edit = edit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(groupName)
                .font(.headline)
                .foregroundStyle(.secondary)

            switch state {
            case .idle:
                Button("今週のお題を表示", action: retry)
            case .loading:
                ProgressView("お題を読み込み中")
            case let .loaded(board):
                Text(board.topic)
                    .font(.largeTitle.weight(.bold))
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 4) {
                    Text("開始 \(board.opensAt.formatted(date: .abbreviated, time: .shortened))")
                    Text("締切 \(board.closesAt.formatted(date: .abbreviated, time: .shortened))")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if let edit, canEdit(board) {
                    Button("お題を変更") {
                        edit(board)
                    }
                }
            case let .failed(message):
                Text(message)
                Button("再試行", action: retry)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
