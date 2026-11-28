import Foundation

struct BoardCursorPosition: Equatable, Sendable {
    let x: Double
    let y: Double

    init(x: Double, y: Double) {
        self.x = min(max(x.isFinite ? x : 0, 0), 1)
        self.y = min(max(y.isFinite ? y : 0, 0), 1)
    }
}

struct BoardEditingMember: Identifiable, Equatable, Sendable {
    let id: UUID
    let displayName: String
    let editingPhotoID: UUID?
}

struct BoardRemoteCursor: Identifiable, Equatable, Sendable {
    let id: UUID
    let displayName: String
    let position: BoardCursorPosition
}

enum BoardPresenceEvent: Equatable, Sendable {
    case connecting
    case connected
    case connectionFailed
    case membersChanged([BoardEditingMember])
    case cursorChanged(userID: UUID, position: BoardCursorPosition?)
    case remoteCursorsCleared
}

protocol BoardPresenceSession: Sendable {
    var events: AsyncStream<BoardPresenceEvent> { get }

    func update(editingPhotoID: UUID?, cursor: BoardCursorPosition?) async
    func disconnect() async
}
