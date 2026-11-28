import Foundation
import Observation

enum BoardPhotoEditorState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(String)
}

@MainActor
@Observable
final class BoardPhotoEditorViewModel {
    private(set) var boardID: UUID?
    private(set) var state: BoardPhotoEditorState = .idle
    private(set) var photos: [BoardPhoto] = []
    private(set) var activePhotoID: UUID?
    private(set) var moveErrorMessage: String?
    private(set) var isEditable = false

    private let currentUserID: UUID
    private let loadSnapshot: @MainActor (UUID) async throws -> BoardSnapshot
    private let grabPhoto: @MainActor (UUID) async throws -> BoardPhotoUpdate
    private let movePhoto: @MainActor (UUID, Double, Double, Double, Double) async throws -> BoardPhotoUpdate
    private let releasePhoto: @MainActor (UUID) async -> Void
    @ObservationIgnored private var loadRequestID: UUID?
    @ObservationIgnored private var grabTasks: [UUID: Task<Bool, Never>] = [:]

    init(
        currentUserID: UUID,
        loadSnapshot: @escaping @MainActor (UUID) async throws -> BoardSnapshot,
        grabPhoto: @escaping @MainActor (UUID) async throws -> BoardPhotoUpdate,
        movePhoto: @escaping @MainActor (UUID, Double, Double, Double, Double) async throws -> BoardPhotoUpdate,
        releasePhoto: @escaping @MainActor (UUID) async -> Void
    ) {
        self.currentUserID = currentUserID
        self.loadSnapshot = loadSnapshot
        self.grabPhoto = grabPhoto
        self.movePhoto = movePhoto
        self.releasePhoto = releasePhoto
    }

    func load(boardID: UUID) async {
        guard !Task.isCancelled else { return }
        let requestID = UUID()
        loadRequestID = requestID
        await cancelActiveMove()
        guard loadRequestID == requestID, !Task.isCancelled else { return }
        self.boardID = boardID
        state = .loading
        moveErrorMessage = nil

        do {
            let snapshot = try await loadSnapshot(boardID)
            guard loadRequestID == requestID, !Task.isCancelled, snapshot.boardID == boardID else { return }
            photos = sorted(snapshot.photos)
            isEditable = snapshot.isOpen && snapshot.closesAt > Date()
            state = .loaded
        } catch is CancellationError {
            guard loadRequestID == requestID else { return }
            state = .idle
        } catch {
            guard loadRequestID == requestID, !Task.isCancelled else { return }
            photos = []
            isEditable = false
            state = .failed(message(for: error, fallbackKey: "boards.photos.load_failed"))
        }
    }

    func reload() async {
        guard let boardID else { return }
        await load(boardID: boardID)
    }

    @discardableResult
    func beginMoving(_ photoID: UUID) -> Bool {
        guard state == .loaded, isEditable, activePhotoID == nil,
              let photo = photos.first(where: { $0.id == photoID }), photo.layer > 0,
              !isLockedByAnotherParticipant(photo)
        else { return false }

        moveErrorMessage = nil
        activePhotoID = photoID
        grabTasks[photoID] = Task { [weak self] in
            guard let self else { return false }
            do {
                let update = try await self.grabPhoto(photoID)
                self.apply(update)
                return true
            } catch is CancellationError {
                return false
            } catch {
                self.moveErrorMessage = self.message(for: error, fallbackKey: "boards.photos.move_failed")
                return false
            }
        }
        return true
    }

    func commitMove(photoID: UUID, x: Double, y: Double) async {
        guard activePhotoID == photoID, let photo = photos.first(where: { $0.id == photoID }) else { return }
        let grabbed = await grabTasks[photoID]?.value ?? false
        grabTasks[photoID] = nil
        guard grabbed, !Task.isCancelled else {
            finishMoving(photoID)
            return
        }

        do {
            let update = try await movePhoto(photoID, x, y, photo.rotation, photo.scale)
            apply(update)
        } catch is CancellationError {
            await releasePhoto(photoID)
        } catch {
            moveErrorMessage = message(for: error, fallbackKey: "boards.photos.move_failed")
            await releasePhoto(photoID)
        }
        finishMoving(photoID)
    }

    func cancelMoving(_ photoID: UUID) async {
        guard activePhotoID == photoID else { return }
        let grabbed = await grabTasks[photoID]?.value ?? false
        grabTasks[photoID] = nil
        if grabbed {
            await releasePhoto(photoID)
        }
        finishMoving(photoID)
    }

    func dismissMoveError() {
        moveErrorMessage = nil
    }

    func isLockedByAnotherParticipant(_ photo: BoardPhoto) -> Bool {
        guard let lockedBy = photo.lockedBy, lockedBy != currentUserID,
              let lockExpiresAt = photo.lockExpiresAt else { return false }
        return lockExpiresAt > Date()
    }

    private func apply(_ update: BoardPhotoUpdate) {
        guard update.boardID == boardID, let index = photos.firstIndex(where: { $0.id == update.id }) else { return }
        photos[index] = photos[index].applying(update)
        photos = sorted(photos)
    }

    private func sorted(_ photos: [BoardPhoto]) -> [BoardPhoto] {
        photos.sorted {
            ($0.layer, $0.zIndex, $0.id.uuidString) < ($1.layer, $1.zIndex, $1.id.uuidString)
        }
    }

    private func cancelActiveMove() async {
        let movingPhotoID = activePhotoID
        let grabbed = if let movingPhotoID {
            await grabTasks[movingPhotoID]?.value ?? false
        } else {
            false
        }
        grabTasks.removeAll()
        activePhotoID = nil
        if grabbed, let movingPhotoID {
            await releasePhoto(movingPhotoID)
        }
    }

    private func finishMoving(_ photoID: UUID) {
        guard activePhotoID == photoID else { return }
        activePhotoID = nil
    }

    private func message(for error: Error, fallbackKey: String.LocalizationValue) -> String {
        switch error as? BoardPhotoEditingError {
        case .forbidden:
            String(localized: "boards.photos.forbidden")
        case .closedBoard:
            String(localized: "boards.photos.closed")
        case .lockedByAnotherParticipant:
            String(localized: "boards.photos.locked")
        case .lostLock:
            String(localized: "boards.photos.lost_lock")
        case .fixedBackground:
            String(localized: "boards.photos.fixed_background")
        case .invalidPosition:
            String(localized: "boards.photos.invalid_position")
        case nil:
            String(localized: fallbackKey)
        }
    }
}
