import Foundation

struct BoardEditingMember: Identifiable, Equatable, Sendable {
    let id: UUID
    let displayName: String
    let editingPhotoID: UUID?
}

enum BoardPresenceEvent: Equatable, Sendable {
    case connecting
    case connected
    case connectionFailed
    case membersChanged([BoardEditingMember])
}

protocol BoardPresenceSession: Sendable {
    var events: AsyncStream<BoardPresenceEvent> { get }

    func setEditingPhotoID(_ photoID: UUID?) async
    func disconnect() async
}
