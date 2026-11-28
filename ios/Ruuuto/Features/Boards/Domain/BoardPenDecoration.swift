import Foundation

struct BoardPenPoint: Equatable, Sendable {
    let x: Double
    let y: Double

    init(x: Double, y: Double) {
        self.x = min(max(x.isFinite ? x : 0, 0), 1)
        self.y = min(max(y.isFinite ? y : 0, 0), 1)
    }
}

struct BoardPenStroke: Equatable, Sendable {
    let points: [BoardPenPoint]
    let colorHex: String
    let width: Double
}

struct BoardPenDecoration: Identifiable, Equatable, Sendable {
    let id: UUID
    let boardID: UUID
    let createdBy: UUID
    let strokes: [BoardPenStroke]
    let x: Double
    let y: Double
    let rotation: Double
    let scale: Double
    let layer: Int
    let zIndex: Int
    let revision: Int64
}
