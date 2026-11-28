import SwiftUI
import UIKit

extension HistoryCalendarViewModel: Identifiable {}

/// 月別カレンダー（RCNO-26）。原案 HTML の「カレンダー（ボードを振り返る）」に合わせ、1年分の12か月をタイルで並べる。
struct HistoryCalendarView: View {
    @State var model: HistoryCalendarViewModel
    let images: PhotoImageCache
    let makeBoard: @MainActor (UUID) -> PastBoardViewModel
    let makeWithdrawal: @MainActor (@escaping @MainActor (UUID) -> Void) -> PhotoWithdrawalViewModel
    let makeMap: @MainActor (UUID) -> CityMapViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    yearHeader
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 14) {
                        ForEach(model.monthsOfYear, id: \.self) { month in
                            monthTile(month)
                        }
                    }
                }
                .padding(20)
            }
            .background(RuuutoPalette.page)
            .navigationTitle(Text("history.title", tableName: "History"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("history.close", tableName: "History") }
                }
            }
            .navigationDestination(for: BoardMonth.self) { month in
                MonthBoardsView(month: month, model: model, images: images, makeBoard: makeBoard, makeWithdrawal: makeWithdrawal, makeMap: makeMap)
            }
            .task { await model.reload() }
        }
    }

    private var yearHeader: some View {
        HStack {
            Button {
                Task { await model.showYear(model.year - 1) }
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel(Text("history.year.previous", tableName: "History"))
            Spacer()
            Text(verbatim: String(model.year))
                .font(RuuutoType.rounded(.largeTitle))
                .foregroundStyle(RuuutoPalette.ink)
            Spacer()
            Button {
                Task { await model.showYear(model.year + 1) }
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!model.canGoToNextYear)
            .accessibilityLabel(Text("history.year.next", tableName: "History"))
        }
        .font(.title2)
        .tint(RuuutoPalette.ink)
    }

    @ViewBuilder private func monthTile(_ month: BoardMonth) -> some View {
        let state = model.state(of: month)
        let boards: [BoardSummary] = if case .loaded(let b) = state { b } else { [] }
        let label = VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(boards.isEmpty ? RuuutoPalette.line.opacity(0.35) : RuuutoPalette.soft)
                if let board = boards.last(where: { !$0.previewPaths.isEmpty }), let path = board.previewPaths.first {
                    StoredPhotoImage(path: path, images: images)
                        .fadedBoard(closedAt: board.isOpen ? nil : board.closesAt)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                if state == .loading { ProgressView() }
                if state == .failed { Image(systemName: "exclamationmark.arrow.circlepath").foregroundStyle(RuuutoPalette.sub) }
            }
            .aspectRatio(1, contentMode: .fit)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(monthName(month))
                    .font(RuuutoType.rounded(.subheadline))
                    .foregroundStyle(model.isFuture(month) ? RuuutoPalette.sub : RuuutoPalette.ink)
                if !boards.isEmpty {
                    Text("history.month.count \(boards.count)", tableName: "History")
                        .font(RuuutoType.body(.caption2, dynamicTypeSize: dynamicTypeSize))
                        .foregroundStyle(RuuutoPalette.sub)
                }
            }
        }
        if model.isFuture(month) {
            label.opacity(0.4).accessibilityHidden(true)
        } else {
            NavigationLink(value: month) { label }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(monthName(month)))
                .accessibilityValue(Text("history.month.count \(boards.count)", tableName: "History"))
        }
    }

    private func monthName(_ month: BoardMonth) -> String {
        monthDate(month).formatted(.dateTime.month(.abbreviated))
    }
}

/// 月の初日（UTC）。月名の表示に使う
func monthDate(_ month: BoardMonth) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: DateComponents(year: month.year, month: month.month, day: 15)) ?? Date()
}

/// 選んだ月の週別ボード
struct MonthBoardsView: View {
    let month: BoardMonth
    let model: HistoryCalendarViewModel
    let images: PhotoImageCache
    let makeBoard: @MainActor (UUID) -> PastBoardViewModel
    let makeWithdrawal: @MainActor (@escaping @MainActor (UUID) -> Void) -> PhotoWithdrawalViewModel
    let makeMap: @MainActor (UUID) -> CityMapViewModel
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            switch model.state(of: month) {
            case .loaded(let boards) where boards.isEmpty:
                ContentUnavailableView {
                    Label { Text("history.month.empty.title", tableName: "History") } icon: { Image(systemName: "calendar") }
                } description: {
                    Text("history.month.empty.message", tableName: "History")
                }
            case .loaded(let boards):
                List(boards) { board in
                    NavigationLink {
                        PastBoardView(model: makeBoard(board.id), images: images, makeWithdrawal: makeWithdrawal, makeMap: makeMap)
                    } label: {
                        row(board)
                    }
                }
            case .failed:
                ContentUnavailableView {
                    Label { Text("history.load_failed", tableName: "History") } icon: { Image(systemName: "wifi.exclamationmark") }
                } actions: {
                    Button { Task { await model.reload(month) } } label: { Text("history.retry", tableName: "History") }
                }
            case .loading, nil:
                ProgressView()
            }
        }
        .navigationTitle(Text(monthDate(month).formatted(.dateTime.year().month(.wide))))
    }

    private func row(_ board: BoardSummary) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(RuuutoPalette.line.opacity(0.4))
                if let path = board.previewPaths.first {
                    StoredPhotoImage(path: path, images: images)
                        .fadedBoard(closedAt: board.isOpen ? nil : board.closesAt)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: board.topic(for: locale))
                    .font(RuuutoType.body(.body, dynamicTypeSize: dynamicTypeSize))
                    .foregroundStyle(RuuutoPalette.ink)
                Text(weekRange(board))
                    .font(RuuutoType.body(.footnote, dynamicTypeSize: dynamicTypeSize))
                    .foregroundStyle(RuuutoPalette.sub)
                Text("history.board.photos \(board.photoCount)", tableName: "History")
                    .font(RuuutoType.body(.caption, dynamicTypeSize: dynamicTypeSize))
                    .foregroundStyle(RuuutoPalette.sub)
            }
        }
    }
}

/// 週の期間を端末の言語と地域で表示する。締切の時刻はその週に含めない
func weekRange(_ board: BoardSummary) -> String {
    let end = board.closesAt.addingTimeInterval(-1)
    return (board.opensAt..<end).formatted(.interval.month(.abbreviated).day())
}

/// Storage の非公開の画像を表示する。読み込み中は薄い面、失敗したら記号を出す
struct StoredPhotoImage: View {
    let path: String
    let images: PhotoImageCache
    var contentMode: ContentMode = .fill
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else if failed {
                Image(systemName: "photo").foregroundStyle(RuuutoPalette.sub)
            } else {
                Rectangle().fill(RuuutoPalette.line.opacity(0.3))
            }
        }
        .task(id: path) {
            do {
                let data = try await images.data(for: path)
                image = UIImage(data: data)
                failed = image == nil
            } catch {
                failed = true
            }
        }
    }
}
