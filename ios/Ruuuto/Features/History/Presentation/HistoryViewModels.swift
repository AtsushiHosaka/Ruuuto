// logic-test
import Foundation
import Observation

/// 月別カレンダー（RCNO-26）。1年分の12か月を並べ、月を選ぶとその月の週別ボードを一覧にする。
@MainActor
@Observable
final class HistoryCalendarViewModel {
    enum MonthState: Equatable {
        case loading
        case loaded([BoardSummary])
        case failed
    }

    let groupID: UUID
    private(set) var year: Int
    private(set) var months: [BoardMonth: MonthState] = [:]
    /// 今の月（UTC）。これより先の月は開けない
    let currentMonth: BoardMonth

    private let loadMonth: @MainActor (BoardMonth) async throws -> [BoardSummary]
    @ObservationIgnored private var yearRequest = UUID()

    init(groupID: UUID, now: Date = Date(), loadMonth: @escaping @MainActor (BoardMonth) async throws -> [BoardSummary]) {
        self.groupID = groupID
        self.loadMonth = loadMonth
        currentMonth = BoardMonth(containing: now)
        year = currentMonth.year
    }

    var monthsOfYear: [BoardMonth] { (1...12).map { BoardMonth(year: year, month: $0) } }
    var canGoToNextYear: Bool { year < currentMonth.year }

    func state(of month: BoardMonth) -> MonthState? { months[month] }

    func isFuture(_ month: BoardMonth) -> Bool { month > currentMonth }

    func showYear(_ newYear: Int) async {
        guard newYear <= currentMonth.year else { return }
        year = newYear
        await reload()
    }

    /// 表示中の年の12か月を読み直す。年を切り替えたあとに前の年の結果が届いても使わない。
    func reload() async {
        let request = UUID()
        yearRequest = request
        let targets = monthsOfYear.filter { !isFuture($0) }
        for month in targets where months[month] == nil || months[month] == .failed { months[month] = .loading }

        // 12か月を同時に取りに行く（結果は月の順に反映する）
        let tasks = targets.map { month in
            Task { @MainActor [loadMonth] in (month, await Self.fetch(month, with: loadMonth)) }
        }
        for task in tasks {
            let (month, state) = await task.value
            guard yearRequest == request, let state else { continue }
            months[month] = state
        }
    }

    private static func fetch(
        _ month: BoardMonth, with loadMonth: @MainActor (BoardMonth) async throws -> [BoardSummary]
    ) async -> MonthState? {
        do {
            let boards = try await loadMonth(month)
            return .loaded(boards.sorted { $0.opensAt < $1.opensAt })
        } catch is CancellationError {
            return nil
        } catch {
            return .failed
        }
    }

    /// 一つの月だけ読み直す（失敗した月の再試行）
    func reload(_ month: BoardMonth) async {
        months[month] = .loading
        do {
            let boards = try await loadMonth(month)
            months[month] = .loaded(boards.sorted { $0.opensAt < $1.opensAt })
        } catch {
            months[month] = .failed
        }
    }
}

/// 読み取り用に開いた1週分のボード（RCNO-26）
@MainActor
@Observable
final class PastBoardViewModel {
    enum State: Equatable {
        case loading
        case loaded(BoardSnapshot)
        case failed
    }

    let boardID: UUID
    private(set) var state: State = .loading
    private let loadSnapshot: @MainActor (UUID) async throws -> BoardSnapshot

    init(boardID: UUID, loadSnapshot: @escaping @MainActor (UUID) async throws -> BoardSnapshot) {
        self.boardID = boardID
        self.loadSnapshot = loadSnapshot
    }

    func load() async {
        state = .loading
        do {
            let snapshot = try await loadSnapshot(boardID)
            state = snapshot.board.id == boardID ? .loaded(snapshot) : .failed
        } catch is CancellationError {
            return
        } catch {
            state = .failed
        }
    }

    /// 取り下げた写真を表示から外す（RCNO-14）
    func removePhoto(_ photoID: UUID) {
        guard case .loaded(let s) = state else { return }
        state = .loaded(BoardSnapshot(board: s.board, photos: s.photos.filter { $0.id != photoID }, decorations: s.decorations))
    }
}
