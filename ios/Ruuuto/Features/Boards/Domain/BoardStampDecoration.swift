import Foundation

enum BoardStampKind: String, CaseIterable, Identifiable, Sendable {
    case heart
    case star
    case sparkles
    case flower
    case smile
    case sun

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .heart: "💗"
        case .star: "⭐️"
        case .sparkles: "✨"
        case .flower: "🌼"
        case .smile: "😊"
        case .sun: "☀️"
        }
    }
}

struct BoardStampDecoration: Identifiable, Equatable, Sendable {
    let id: UUID
    let boardID: UUID
    let createdBy: UUID
    let stamp: BoardStampKind
    let x: Double
    let y: Double
    let rotation: Double
    let scale: Double
    let layer: Int
    let zIndex: Int
    let revision: Int64
}

struct BoardStampPlacement: Equatable, Sendable {
    let stamp: BoardStampKind
    let x: Double
    let y: Double

    init(stamp: BoardStampKind, x: Double, y: Double) {
        self.stamp = stamp
        self.x = min(max(x.isFinite ? x : 0, 0), 1)
        self.y = min(max(y.isFinite ? y : 0, 0), 1)
    }
}
