// logic-test
import Foundation
import Observation

/// 自分の写真の取り下げ（RCNO-14）。ボード、過去のボード、マップの写真が同じ処理を使う。
///
/// 確認してから取り下げる。成功したら呼び出し元に知らせ、表示から消してもらう。
/// 失敗したら写真は表示したまま、再試行を案内する。
@MainActor
@Observable
final class PhotoWithdrawalViewModel {
    struct Target: Equatable, Sendable {
        let photoID: UUID
        let storagePath: String
    }

    enum State: Equatable {
        case idle
        case confirming(Target)
        case withdrawing(Target)
        case failed(Target, PhotoPostError)
    }

    let userID: UUID
    private(set) var state: State = .idle
    private let withdrawer: PhotoWithdrawer
    private let onWithdrawn: @MainActor (UUID) -> Void

    init(userID: UUID, withdrawer: PhotoWithdrawer, onWithdrawn: @escaping @MainActor (UUID) -> Void = { _ in }) {
        self.userID = userID
        self.withdrawer = withdrawer
        self.onWithdrawn = onWithdrawn
    }

    /// 取り下げの操作を表示するのは、自分が投稿した写真だけ。最終的な判定はサーバーが行う（42501）。
    func canWithdraw(postedBy: UUID) -> Bool { postedBy == userID }

    var isWithdrawing: Bool {
        if case .withdrawing = state { return true }
        return false
    }

    func request(_ target: Target) {
        guard !isWithdrawing else { return }
        state = .confirming(target)
    }

    func dismiss() {
        guard !isWithdrawing else { return }
        state = .idle
    }

    /// 確認ダイアログの「取り下げる」と、失敗後の再試行から呼ぶ。
    /// 対象は引数で受け取る（ダイアログを閉じる処理と順番が前後しても対象を失わないため）。
    @discardableResult
    func confirm(_ target: Target) async -> Bool {
        guard !isWithdrawing else { return false }
        state = .withdrawing(target)
        do {
            let photo = try await withdrawer.withdraw(target.photoID)
            guard photo.id == target.photoID, photo.status == .withdrawn else { throw PhotoPostError.rejected }
        } catch is CancellationError {
            state = .confirming(target)
            return false
        } catch {
            state = .failed(target, error as? PhotoPostError ?? .retryable)
            return false
        }

        // 画像の削除に失敗しても、写真はもう誰にも見えない（RLS）。消し残しは定期処理が消す。
        try? await withdrawer.removeImage(target.storagePath)
        state = .idle
        onWithdrawn(target.photoID)
        return true
    }
}
