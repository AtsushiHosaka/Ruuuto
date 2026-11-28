// logic-test
import Foundation

/// 月別カレンダーに並べる週のボード（ruuuto_board_history、RCNO-43）
struct BoardSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let topic: String
    /// 固定のお題の言語別の本文。手動のお題は空（RCNO-4）
    let topicTexts: [String: String]
    let opensAt: Date
    let closesAt: Date
    let isOpen: Bool
    let photoCount: Int
    /// 投稿済みの写真の保存先。古い順に最大3件
    let previewPaths: [String]

    /// 表示のルール（RCNO-4）: 端末の言語のキーがあればそれ、なければ ja、それもなければ topic
    func topic(for locale: Locale) -> String {
        if let code = locale.language.languageCode?.identifier, let text = topicTexts[code] { return text }
        return topicTexts["ja"] ?? topic
    }
}

/// カレンダーの年と月。ボードは「開始日時（UTC）の月」に属する（RCNO-10、RCNO-43）。
/// 週が月や年をまたいでも、月の区分はサーバーに合わせる。
struct BoardMonth: Hashable, Comparable, Sendable {
    let year: Int
    let month: Int

    init(year: Int, month: Int) {
        // 13月は翌年1月、0月は前年12月にそろえる
        let index = year * 12 + (month - 1)
        self.year = Int((Double(index) / 12).rounded(.down))
        self.month = index - self.year * 12 + 1
    }

    /// その時点を含む月（UTC）
    init(containing date: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month], from: date)
        self.init(year: parts.year!, month: parts.month!)
    }

    func adding(months: Int) -> BoardMonth { BoardMonth(year: year, month: month + months) }

    static func < (a: BoardMonth, b: BoardMonth) -> Bool { (a.year, a.month) < (b.year, b.month) }
}

/// 読み取り用に開く1週分のボード（ruuuto_board_snapshot）
struct BoardSnapshot: Equatable, Sendable {
    let board: BoardSummary
    let photos: [BoardPhoto]
    let decorations: [BoardDecoration]
}

/// ボード上の配置。座標の単位はボード担当と調整中なので、解釈は BoardGeometry だけで行う。
struct BoardPlacement: Equatable, Sendable {
    let x: Double
    let y: Double
    let rotation: Double
    let scale: Double
    let layer: Int
    let zIndex: Int
}

struct BoardPhoto: Identifiable, Equatable, Sendable {
    let id: UUID
    let postedBy: UUID
    let storagePath: String
    let city: String?
    let width: Int?
    let height: Int?
    let placement: BoardPlacement
}

struct BoardDecoration: Identifiable, Equatable, Sendable {
    enum Content: Equatable, Sendable {
        case text(String, colorHex: String?)
        case stamp(String)
        case pen([Stroke])
        /// 知らない種類。表示しない
        case unknown
    }

    struct Stroke: Equatable, Sendable {
        let points: [[Double]]
        let colorHex: String?
        let width: Double
    }

    let id: UUID
    let createdBy: UUID
    let content: Content
    let placement: BoardPlacement
}
