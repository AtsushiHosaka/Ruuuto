// logic-test
import Foundation
import Observation

/// 写真1枚の投稿（RCNO-13）。ライブラリと撮影（RCNO-16）の両方がこの処理を使う。
///
/// 流れ: 写真を選ぶ → アップロード用に作り直す（RCNO-30） → プレビュー → 投稿（開始・アップロード・確定）
/// 失敗しても選んだ写真と投稿IDを保持するので、同じ写真を重複させずに送り直せる（RCNO-15）。
@MainActor
@Observable
final class PhotoPostViewModel {
    enum Step: Int, Equatable, Sendable {
        case starting = 1
        case uploading = 2
        case finishing = 3

        static let count = 3
    }

    enum Failure: Equatable, Sendable {
        /// 写真を読めなかった、または大きすぎる。別の写真を選ぶ
        case preparation(PhotoPreparationError)
        case post(PhotoPostError)
    }

    enum State: Equatable {
        /// 写真をまだ選んでいない
        case choosing
        case preparing
        case previewing(PreparedPhoto)
        case posting(PreparedPhoto, Step)
        case failed(PreparedPhoto?, Failure)
        case posted(PostedPhoto)
    }

    let boardID: UUID
    private(set) var state: State = .choosing

    /// 投稿IDは写真を選んだ時点で決める。同じ写真の送り直しでは同じIDを使う。
    @ObservationIgnored private(set) var photoID = UUID()
    @ObservationIgnored private var selectionID = UUID()
    private let prepare: @Sendable (Data) throws -> PreparedPhoto
    private let poster: PhotoPoster
    private let onPosted: @MainActor (PostedPhoto) -> Void
    private let pendingStore: PendingPhotoStore?

    init(
        boardID: UUID,
        poster: PhotoPoster,
        pendingStore: PendingPhotoStore? = nil,
        prepare: @escaping @Sendable (Data) throws -> PreparedPhoto = PhotoImagePreparer.prepare,
        onPosted: @escaping @MainActor (PostedPhoto) -> Void = { _ in }
    ) {
        self.boardID = boardID
        self.poster = poster
        self.pendingStore = pendingStore
        self.prepare = prepare
        self.onPosted = onPosted

        // 前回送れなかった写真があれば、同じ投稿IDで送り直せる状態に戻す（RCNO-15）
        if let (entry, photo) = pendingStore?.latest(boardID: boardID) {
            photoID = entry.photoID
            state = .failed(photo, .post(.retryable))
        }
    }

    var preparedPhoto: PreparedPhoto? {
        switch state {
        case .previewing(let photo), .posting(let photo, _): photo
        case .failed(let photo, _): photo
        case .choosing, .preparing, .posted: nil
        }
    }

    var isPosting: Bool {
        if case .posting = state { return true }
        return false
    }

    var canSubmit: Bool {
        switch state {
        case .previewing: true
        case .failed(let photo, .post(let error)): photo != nil && error.canRetry
        default: false
        }
    }

    /// 選んだ写真を読み込む。前の写真の結果が遅れて届いても使わない。
    func select(_ original: Data) async {
        guard !isPosting else { return }
        let selection = UUID()
        selectionID = selection
        discardPending()
        photoID = UUID()
        state = .preparing

        let prepare = self.prepare
        let result: Result<PreparedPhoto, PhotoPreparationError> = await Task.detached(priority: .userInitiated) {
            do { return .success(try prepare(original)) }
            catch let error as PhotoPreparationError { return .failure(error) }
            catch { return .failure(.unreadable) }
        }.value

        guard selectionID == selection else { return }
        switch result {
        case .success(let photo): state = .previewing(photo)
        case .failure(let error): state = .failed(nil, .preparation(error))
        }
    }

    /// 写真の読み込みに失敗した（ライブラリから取り出せなかった等）
    func selectionFailed() {
        guard !isPosting else { return }
        selectionID = UUID()
        state = .failed(nil, .preparation(.unreadable))
    }

    /// 選んだ写真を取り消す。投稿中は取り消せない（サーバー側の結果と食い違うため）。
    func cancelSelection() {
        guard !isPosting else { return }
        selectionID = UUID()
        discardPending()
        photoID = UUID()
        state = .choosing
    }

    private func discardPending() {
        pendingStore?.remove(photoID: photoID)
    }

    @discardableResult
    func submit(city: String? = nil) async -> PostedPhoto? {
        guard canSubmit, let photo = preparedPhoto else { return nil }
        let photoID = self.photoID
        let selection = selectionID

        do {
            state = .posting(photo, .starting)
            // 送信中にアプリが終了・再起動しても、同じIDで送り直せるよう先に残す。確定したら消す。
            try? pendingStore?.save(photoID: photoID, boardID: boardID, photo: photo)
            var posted = try await poster.begin(photoID, boardID, city, photo.width, photo.height)
            // 前回の送り直しで確定まで済んでいれば、アップロードと確定は省く
            if posted.status == .pending {
                guard selectionID == selection else { return nil }
                state = .posting(photo, .uploading)
                try await poster.upload(posted.storagePath, photo.data)
                guard selectionID == selection else { return nil }
                state = .posting(photo, .finishing)
                posted = try await poster.finish(photoID)
            }
            guard selectionID == selection else { return nil }
            guard posted.status == .posted, posted.id == photoID, posted.boardID == boardID else {
                throw PhotoPostError.rejected
            }
            discardPending()
            state = .posted(posted)
            onPosted(posted)
            return posted
        } catch is CancellationError {
            if selectionID == selection { state = .previewing(photo) }
            return nil
        } catch {
            let failure = error as? PhotoPostError ?? .retryable
            // 送り直せる失敗は残したまま（画面を閉じても言語を変えても戻せる）。通らない失敗は消す。
            if !failure.canRetry {
                pendingStore?.remove(photoID: photoID)
            }
            if selectionID == selection {
                state = .failed(photo, .post(failure))
            }
            return nil
        }
    }
}
