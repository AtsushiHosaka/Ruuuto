import Foundation

struct BoardTextDecoration: Identifiable, Equatable, Sendable {
    let id: UUID
    let boardID: UUID
    let createdBy: UUID
    let text: String
    let colorHex: String
    let x: Double
    let y: Double
    let rotation: Double
    let scale: Double
    let layer: Int
    let zIndex: Int
    let revision: Int64
}

enum BoardDecorationEditingError: Error, Equatable, Sendable {
    case forbidden
    case closedBoard
    case duplicateID
    case invalidContent
    case lockedByAnotherParticipant
    case lostLock
    case immutable
    case fixedBackground
}
