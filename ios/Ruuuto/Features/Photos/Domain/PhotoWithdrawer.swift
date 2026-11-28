// logic-test
import Foundation

/// 写真の取り下げ（RCNO-14、サーバーは RCNO-35）
struct PhotoWithdrawer: Sendable {
    /// 写真を「取り下げ済み」にする。本人だけ、締切後も可。何度呼んでも同じ結果
    var withdraw: @Sendable (_ photoID: UUID) async throws -> PostedPhoto
    /// Storage の画像を消す。失敗しても定期処理（photo-cleanup）が後で消す
    var removeImage: @Sendable (_ storagePath: String) async throws -> Void
}
