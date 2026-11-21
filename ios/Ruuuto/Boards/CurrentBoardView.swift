import SwiftUI

struct CurrentBoardView: View {
    let groupName: String
    let state: CurrentBoardState
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(groupName)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(RuuutoPalette.muted)

            switch state {
            case .idle:
                boardAction("今週のお題を表示", action: retry)
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(RuuutoPalette.accent)
                        .accessibilityHidden(true)
                    Text("お題を読み込み中")
                }
            case let .loaded(board):
                Text(board.topic)
                    .font(.system(.title, design: .rounded).weight(.heavy))
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        "締切 \(board.closesAt.formatted(date: .abbreviated, time: .shortened))",
                        systemImage: "clock"
                    )
                    Text("開始 \(board.opensAt.formatted(date: .abbreviated, time: .shortened))")
                }
                .font(.footnote)
                .foregroundStyle(RuuutoPalette.muted)
            case let .failed(message):
                Text(message)
                boardAction("再試行", action: retry)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RuuutoPalette.ink, in: RoundedRectangle(cornerRadius: 20))
    }

    private func boardAction(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(RuuutoPalette.ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(RuuutoPalette.accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
