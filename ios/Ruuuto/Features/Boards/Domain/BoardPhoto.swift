import Foundation

struct BoardPhoto: Identifiable, Equatable, Sendable {
    let id: UUID
    let boardID: UUID
    let postedBy: UUID
    let imageURL: URL
    let city: String?
    let pixelWidth: Int?
    let pixelHeight: Int?
    var x: Double
    var y: Double
    var rotation: Double
    var scale: Double
    var layer: Int
    var zIndex: Int
    var revision: Int64
    var lockedBy: UUID?
    var lockExpiresAt: Date?

    var aspectRatio: Double {
        guard let pixelWidth, let pixelHeight, pixelWidth > 0, pixelHeight > 0 else { return 1 }
        return Double(pixelWidth) / Double(pixelHeight)
    }

    func applying(_ update: BoardPhotoUpdate) -> BoardPhoto {
        var copy = self
        copy.x = update.x
        copy.y = update.y
        copy.rotation = update.rotation
        copy.scale = update.scale
        copy.layer = update.layer
        copy.zIndex = update.zIndex
        copy.revision = update.revision
        copy.lockedBy = update.lockedBy
        copy.lockExpiresAt = update.lockExpiresAt
        return copy
    }

    func applying(_ change: BoardPhotoSavedChange) -> BoardPhoto {
        var copy = self
        copy.x = change.x
        copy.y = change.y
        copy.rotation = change.rotation
        copy.scale = change.scale
        copy.layer = change.layer
        copy.zIndex = change.zIndex
        copy.revision = change.revision
        return copy
    }
}

struct BoardPhotoUpdate: Equatable, Sendable {
    let id: UUID
    let boardID: UUID
    let x: Double
    let y: Double
    let rotation: Double
    let scale: Double
    let layer: Int
    let zIndex: Int
    let revision: Int64
    let lockedBy: UUID?
    let lockExpiresAt: Date?
}

struct BoardPhotoSavedChange: Equatable, Sendable {
    let id: UUID
    let boardID: UUID
    let x: Double
    let y: Double
    let rotation: Double
    let scale: Double
    let layer: Int
    let zIndex: Int
    let revision: Int64
}

enum BoardPhotoSyncEvent: Equatable, Sendable {
    case connecting
    case connected
    case connectionFailed
    case photoSaved(BoardPhotoSavedChange)
    case photoWithdrawn(boardID: UUID, photoID: UUID)
    case snapshotRequired
}

struct BoardSnapshot: Equatable, Sendable {
    let boardID: UUID
    let isOpen: Bool
    let closesAt: Date
    let photos: [BoardPhoto]
}

enum BoardPhotoEditingError: Error, Equatable, Sendable {
    case forbidden
    case closedBoard
    case lockedByAnotherParticipant
    case lostLock
    case fixedBackground
    case invalidPosition
}
