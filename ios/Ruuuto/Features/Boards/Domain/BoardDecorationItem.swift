import Foundation

enum BoardDecorationItem: Identifiable, Equatable, Sendable {
    case text(BoardTextDecoration)
    case stamp(BoardStampDecoration)
    case pen(BoardPenDecoration)

    var id: UUID {
        switch self {
        case .text(let value): value.id
        case .stamp(let value): value.id
        case .pen(let value): value.id
        }
    }

    var boardID: UUID {
        switch self {
        case .text(let value): value.boardID
        case .stamp(let value): value.boardID
        case .pen(let value): value.boardID
        }
    }

    var createdBy: UUID {
        switch self {
        case .text(let value): value.createdBy
        case .stamp(let value): value.createdBy
        case .pen(let value): value.createdBy
        }
    }

    var x: Double {
        switch self {
        case .text(let value): value.x
        case .stamp(let value): value.x
        case .pen(let value): value.x
        }
    }

    var y: Double {
        switch self {
        case .text(let value): value.y
        case .stamp(let value): value.y
        case .pen(let value): value.y
        }
    }

    var rotation: Double {
        switch self {
        case .text(let value): value.rotation
        case .stamp(let value): value.rotation
        case .pen(let value): value.rotation
        }
    }

    var scale: Double {
        switch self {
        case .text(let value): value.scale
        case .stamp(let value): value.scale
        case .pen(let value): value.scale
        }
    }

    var isMovable: Bool {
        if case .pen = self { return false }
        return true
    }
}
