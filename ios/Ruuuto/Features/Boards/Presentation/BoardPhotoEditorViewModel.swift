import Foundation
import Observation

enum BoardPhotoEditorState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(String)
}

enum BoardPhotoSyncState: Equatable, Sendable {
    case idle
    case connecting
    case connected
    case reconnecting
}

@MainActor
@Observable
final class BoardPhotoEditorViewModel {
    private(set) var boardID: UUID?
    private(set) var state: BoardPhotoEditorState = .idle
    private(set) var photos: [BoardPhoto] = []
    private(set) var textDecorations: [BoardTextDecoration] = []
    private(set) var penDecorations: [BoardPenDecoration] = []
    private(set) var pendingPenStroke: [BoardPenPoint]?
    private(set) var stampDecorations: [BoardStampDecoration] = []
    private(set) var pendingStampPlacement: BoardStampPlacement?
    private(set) var activePhotoID: UUID?
    private(set) var moveErrorMessage: String?
    private(set) var textErrorMessage: String?
    private(set) var isSavingText = false
    private(set) var penErrorMessage: String?
    private(set) var isSavingPen = false
    private(set) var stampErrorMessage: String?
    private(set) var isSavingStamp = false
    private(set) var isEditable = false
    private(set) var syncState: BoardPhotoSyncState = .idle

    private let currentUserID: UUID
    private let loadSnapshot: @MainActor (UUID) async throws -> BoardSnapshot
    private let grabPhoto: @MainActor (UUID) async throws -> BoardPhotoUpdate
    private let movePhoto: @MainActor (UUID, Double, Double, Double, Double) async throws -> BoardPhotoUpdate
    private let releasePhoto: @MainActor (UUID) async -> Void
    private let createTextDecoration: @MainActor (UUID, UUID, String, Double, Double) async throws -> BoardTextDecoration
    private let createPenDecoration: @MainActor (UUID, UUID, [BoardPenPoint]) async throws -> BoardPenDecoration
    private let createStampDecoration: @MainActor (
        UUID,
        UUID,
        BoardStampKind,
        Double,
        Double
    ) async throws -> BoardStampDecoration
    private let observeBoard: @MainActor (UUID) -> AsyncStream<BoardPhotoSyncEvent>
    @ObservationIgnored private var loadRequestID: UUID?
    @ObservationIgnored private var grabTasks: [UUID: Task<Bool, Never>] = [:]
    @ObservationIgnored private var pendingTextAddition: PendingTextAddition?
    @ObservationIgnored private var pendingPenAddition: PendingPenAddition?
    @ObservationIgnored private var pendingStampAddition: PendingStampAddition?

    init(
        currentUserID: UUID,
        loadSnapshot: @escaping @MainActor (UUID) async throws -> BoardSnapshot,
        grabPhoto: @escaping @MainActor (UUID) async throws -> BoardPhotoUpdate,
        movePhoto: @escaping @MainActor (UUID, Double, Double, Double, Double) async throws -> BoardPhotoUpdate,
        releasePhoto: @escaping @MainActor (UUID) async -> Void,
        addText: @escaping @MainActor (UUID, UUID, String, Double, Double) async throws -> BoardTextDecoration,
        addPen: @escaping @MainActor (UUID, UUID, [BoardPenPoint]) async throws -> BoardPenDecoration,
        addStamp: @escaping @MainActor (
            UUID,
            UUID,
            BoardStampKind,
            Double,
            Double
        ) async throws -> BoardStampDecoration,
        observeBoard: @escaping @MainActor (UUID) -> AsyncStream<BoardPhotoSyncEvent>
    ) {
        self.currentUserID = currentUserID
        self.loadSnapshot = loadSnapshot
        self.grabPhoto = grabPhoto
        self.movePhoto = movePhoto
        self.releasePhoto = releasePhoto
        createTextDecoration = addText
        createPenDecoration = addPen
        createStampDecoration = addStamp
        self.observeBoard = observeBoard
    }

    func synchronize(boardID: UUID) async {
        guard !Task.isCancelled else { return }
        let requestID = UUID()
        loadRequestID = requestID
        await cancelActiveMove()
        guard loadRequestID == requestID, !Task.isCancelled else { return }
        let changedBoard = self.boardID != boardID
        self.boardID = boardID
        state = .loading
        syncState = .connecting
        moveErrorMessage = nil
        textErrorMessage = nil
        penErrorMessage = nil
        stampErrorMessage = nil
        if changedBoard {
            photos = []
            textDecorations = []
            penDecorations = []
            pendingPenStroke = nil
            stampDecorations = []
            pendingStampPlacement = nil
            pendingTextAddition = nil
            pendingPenAddition = nil
            pendingStampAddition = nil
            isEditable = false
        }

        for await event in observeBoard(boardID) {
            guard loadRequestID == requestID, !Task.isCancelled else { break }
            switch event {
            case .connecting:
                syncState = state == .loaded ? .reconnecting : .connecting
            case .connected:
                await refreshSnapshot(boardID: boardID, requestID: requestID)
                guard loadRequestID == requestID, !Task.isCancelled else { break }
                syncState = .connected
            case .connectionFailed:
                syncState = state == .loaded ? .reconnecting : .connecting
                if state != .loaded {
                    state = .failed(String(localized: "boards.photos.load_failed"))
                }
            case .photoSaved(let change):
                await apply(change, boardID: boardID, requestID: requestID)
            case .photoWithdrawn(let eventBoardID, let photoID):
                applyWithdrawal(boardID: eventBoardID, photoID: photoID)
            case .decorationSaved(let decoration):
                apply(decoration)
            case .penDecorationSaved(let decoration):
                apply(decoration)
            case .stampDecorationSaved(let decoration):
                apply(decoration)
            case .decorationDeleted(let eventBoardID, let decorationID):
                applyDecorationDeletion(boardID: eventBoardID, decorationID: decorationID)
            case .snapshotRequired:
                await refreshSnapshot(boardID: boardID, requestID: requestID)
            }
        }

        if loadRequestID == requestID {
            syncState = .idle
            if Task.isCancelled, state == .loading {
                state = .idle
            }
        }
    }

    func reload() async {
        guard let boardID, let requestID = loadRequestID else { return }
        if syncState == .connected {
            await refreshSnapshot(boardID: boardID, requestID: requestID)
        } else {
            state = .loading
        }
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

    @discardableResult
    func addText(_ text: String, x: Double, y: Double) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 200 else {
            textErrorMessage = String(localized: "boards.decorations.text.invalid")
            return false
        }
        guard let boardID, state == .loaded, isEditable, !isSavingText else {
            if !isEditable {
                textErrorMessage = String(localized: "boards.photos.closed")
            }
            return false
        }

        isSavingText = true
        textErrorMessage = nil
        defer { isSavingText = false }
        let request: PendingTextAddition
        if let pendingTextAddition,
           pendingTextAddition.boardID == boardID,
           pendingTextAddition.text == trimmed,
           pendingTextAddition.x == x,
           pendingTextAddition.y == y {
            request = pendingTextAddition
        } else {
            request = PendingTextAddition(
                id: UUID(),
                boardID: boardID,
                text: trimmed,
                x: x,
                y: y
            )
            pendingTextAddition = request
        }
        do {
            let decoration = try await createTextDecoration(request.id, boardID, trimmed, x, y)
            guard decoration.boardID == boardID else {
                textErrorMessage = String(localized: "boards.decorations.text.add_failed")
                return false
            }
            pendingTextAddition = nil
            apply(decoration)
            return true
        } catch is CancellationError {
            return false
        } catch {
            textErrorMessage = decorationMessage(for: error)
            return false
        }
    }

    func dismissTextError() {
        textErrorMessage = nil
    }

    @discardableResult
    func savePenStroke(_ points: [BoardPenPoint]) async -> Bool {
        guard points.count >= 2 else { return false }
        guard let boardID, state == .loaded, isEditable, !isSavingPen else {
            if !isEditable {
                penErrorMessage = String(localized: "boards.photos.closed")
            }
            return false
        }

        let request: PendingPenAddition
        if let pendingPenAddition,
           pendingPenAddition.boardID == boardID,
           pendingPenAddition.points == points {
            request = pendingPenAddition
        } else {
            request = PendingPenAddition(id: UUID(), boardID: boardID, points: points)
            pendingPenAddition = request
        }
        pendingPenStroke = points
        isSavingPen = true
        penErrorMessage = nil
        defer { isSavingPen = false }

        do {
            let decoration = try await createPenDecoration(request.id, boardID, points)
            guard decoration.boardID == boardID else {
                penErrorMessage = String(localized: "boards.decorations.pen.add_failed")
                return false
            }
            pendingPenAddition = nil
            pendingPenStroke = nil
            apply(decoration)
            return true
        } catch is CancellationError {
            return false
        } catch {
            penErrorMessage = decorationMessage(
                for: error,
                invalidKey: "boards.decorations.pen.invalid",
                failureKey: "boards.decorations.pen.add_failed"
            )
            return false
        }
    }

    @discardableResult
    func retryPendingPenStroke() async -> Bool {
        guard let pendingPenStroke else { return false }
        return await savePenStroke(pendingPenStroke)
    }

    func discardPendingPenStroke() {
        guard !isSavingPen else { return }
        pendingPenAddition = nil
        pendingPenStroke = nil
        penErrorMessage = nil
    }

    @discardableResult
    func addStamp(_ stamp: BoardStampKind, x: Double, y: Double) async -> Bool {
        guard let boardID, state == .loaded, isEditable, !isSavingStamp else {
            if !isEditable {
                stampErrorMessage = String(localized: "boards.photos.closed")
            }
            return false
        }

        let placement = BoardStampPlacement(stamp: stamp, x: x, y: y)
        let request: PendingStampAddition
        if let pendingStampAddition,
           pendingStampAddition.boardID == boardID,
           pendingStampAddition.placement == placement {
            request = pendingStampAddition
        } else {
            request = PendingStampAddition(id: UUID(), boardID: boardID, placement: placement)
            pendingStampAddition = request
        }
        pendingStampPlacement = placement
        isSavingStamp = true
        stampErrorMessage = nil
        defer { isSavingStamp = false }

        do {
            let decoration = try await createStampDecoration(
                request.id,
                boardID,
                stamp,
                placement.x,
                placement.y
            )
            guard decoration.boardID == boardID else {
                stampErrorMessage = String(localized: "boards.decorations.stamp.add_failed")
                return false
            }
            pendingStampAddition = nil
            pendingStampPlacement = nil
            apply(decoration)
            return true
        } catch is CancellationError {
            return false
        } catch {
            stampErrorMessage = decorationMessage(
                for: error,
                invalidKey: "boards.decorations.stamp.invalid",
                failureKey: "boards.decorations.stamp.add_failed"
            )
            return false
        }
    }

    @discardableResult
    func retryPendingStamp() async -> Bool {
        guard let placement = pendingStampPlacement else { return false }
        return await addStamp(placement.stamp, x: placement.x, y: placement.y)
    }

    func discardPendingStamp() {
        guard !isSavingStamp else { return }
        pendingStampAddition = nil
        pendingStampPlacement = nil
        stampErrorMessage = nil
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

    private func apply(_ decoration: BoardTextDecoration) {
        guard decoration.boardID == boardID else { return }
        if let index = textDecorations.firstIndex(where: { $0.id == decoration.id }) {
            guard decoration.revision >= textDecorations[index].revision else { return }
            textDecorations[index] = decoration
        } else {
            textDecorations.append(decoration)
        }
        textDecorations = sorted(textDecorations)
    }

    private func apply(_ decoration: BoardPenDecoration) {
        guard decoration.boardID == boardID else { return }
        if let index = penDecorations.firstIndex(where: { $0.id == decoration.id }) {
            guard decoration.revision >= penDecorations[index].revision else { return }
            penDecorations[index] = decoration
        } else {
            penDecorations.append(decoration)
        }
        penDecorations = sorted(penDecorations)
    }

    private func apply(_ decoration: BoardStampDecoration) {
        guard decoration.boardID == boardID else { return }
        if let index = stampDecorations.firstIndex(where: { $0.id == decoration.id }) {
            guard decoration.revision >= stampDecorations[index].revision else { return }
            stampDecorations[index] = decoration
        } else {
            stampDecorations.append(decoration)
        }
        stampDecorations = sorted(stampDecorations)
    }

    private func apply(_ change: BoardPhotoSavedChange, boardID: UUID, requestID: UUID) async {
        guard change.boardID == self.boardID, change.boardID == boardID else { return }
        guard let index = photos.firstIndex(where: { $0.id == change.id }) else {
            await refreshSnapshot(boardID: boardID, requestID: requestID)
            return
        }
        guard change.revision > photos[index].revision else { return }
        photos[index] = photos[index].applying(change)
        photos = sorted(photos)
    }

    private func applyWithdrawal(boardID: UUID, photoID: UUID) {
        guard boardID == self.boardID else { return }
        grabTasks[photoID]?.cancel()
        grabTasks[photoID] = nil
        if activePhotoID == photoID {
            activePhotoID = nil
        }
        photos.removeAll { $0.id == photoID }
    }

    private func applyDecorationDeletion(boardID: UUID, decorationID: UUID) {
        guard boardID == self.boardID else { return }
        textDecorations.removeAll { $0.id == decorationID }
        penDecorations.removeAll { $0.id == decorationID }
        stampDecorations.removeAll { $0.id == decorationID }
    }

    private func refreshSnapshot(boardID: UUID, requestID: UUID) async {
        do {
            let snapshot = try await loadSnapshot(boardID)
            guard loadRequestID == requestID, !Task.isCancelled, snapshot.boardID == boardID else { return }
            photos = sorted(snapshot.photos)
            textDecorations = sorted(snapshot.textDecorations)
            penDecorations = sorted(snapshot.penDecorations)
            stampDecorations = sorted(snapshot.stampDecorations)
            isEditable = snapshot.isOpen && snapshot.closesAt > Date()
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard loadRequestID == requestID, !Task.isCancelled else { return }
            if state != .loaded {
                photos = []
                textDecorations = []
                penDecorations = []
                stampDecorations = []
                isEditable = false
                state = .failed(message(for: error, fallbackKey: "boards.photos.load_failed"))
            }
        }
    }

    private func sorted(_ photos: [BoardPhoto]) -> [BoardPhoto] {
        photos.sorted {
            ($0.layer, $0.zIndex, $0.id.uuidString) < ($1.layer, $1.zIndex, $1.id.uuidString)
        }
    }

    private func sorted(_ decorations: [BoardTextDecoration]) -> [BoardTextDecoration] {
        decorations.sorted {
            ($0.layer, $0.zIndex, $0.id.uuidString) < ($1.layer, $1.zIndex, $1.id.uuidString)
        }
    }

    private func sorted(_ decorations: [BoardPenDecoration]) -> [BoardPenDecoration] {
        decorations.sorted {
            ($0.layer, $0.zIndex, $0.id.uuidString) < ($1.layer, $1.zIndex, $1.id.uuidString)
        }
    }

    private func sorted(_ decorations: [BoardStampDecoration]) -> [BoardStampDecoration] {
        decorations.sorted {
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

    private func decorationMessage(
        for error: Error,
        invalidKey: String.LocalizationValue = "boards.decorations.text.invalid",
        failureKey: String.LocalizationValue = "boards.decorations.text.add_failed"
    ) -> String {
        switch error as? BoardDecorationEditingError {
        case .forbidden:
            String(localized: "boards.photos.forbidden")
        case .closedBoard:
            String(localized: "boards.photos.closed")
        case .invalidContent:
            String(localized: invalidKey)
        case .duplicateID, nil:
            String(localized: failureKey)
        }
    }
}

private struct PendingTextAddition: Equatable, Sendable {
    let id: UUID
    let boardID: UUID
    let text: String
    let x: Double
    let y: Double
}

private struct PendingPenAddition: Equatable, Sendable {
    let id: UUID
    let boardID: UUID
    let points: [BoardPenPoint]
}

private struct PendingStampAddition: Equatable, Sendable {
    let id: UUID
    let boardID: UUID
    let placement: BoardStampPlacement
}
