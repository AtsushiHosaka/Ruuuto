// logic-test
import Foundation

/// サーバーに登録された写真（ruuuto_begin_photo / ruuuto_finish_photo の戻り値）
struct PostedPhoto: Identifiable, Equatable, Sendable {
    enum Status: String, Sendable {
        case pending
        case posted
        case withdrawn
    }

    let id: UUID
    let boardID: UUID
    let postedBy: UUID
    let storagePath: String
    let status: Status
    let city: String?
    let width: Int?
    let height: Int?
}

/// 投稿の失敗。サーバーのエラーコード（RCNO-35、RCNO-27）を画面で扱える形にしたもの。
enum PhotoPostError: Error, Equatable {
    /// 締切を過ぎた（RC002）。送り直しても投稿できない
    case boardClosed
    /// 同じ写真が取り下げ済み（RC010）
    case withdrawn
    /// ボードに所属していない、または権限がない（42501）
    case forbidden
    /// 入力が正しくない（RC008）、同じIDの別の写真（RC009）
    case rejected
    /// 通信の失敗、画像の未到着（RC007）など。同じ写真で送り直せる
    case retryable

    var canRetry: Bool { self == .retryable }
}

/// 投稿の3段階（RCNO-35）。Data層の実装を画面から差し替えられるよう、操作だけを持つ。
struct PhotoPoster: Sendable {
    /// 写真の行を「投稿途中」で作る。同じIDなら既存の行を返す
    var begin: @Sendable (_ photoID: UUID, _ boardID: UUID, _ city: String?, _ width: Int, _ height: Int) async throws -> PostedPhoto
    /// 画像を Storage の storage_path に置く。投稿途中なら上書きできる
    var upload: @Sendable (_ storagePath: String, _ data: Data) async throws -> Void
    /// 画像の到着を確かめて「投稿済み」にする。同じIDなら同じ結果を返す
    var finish: @Sendable (_ photoID: UUID) async throws -> PostedPhoto
}
