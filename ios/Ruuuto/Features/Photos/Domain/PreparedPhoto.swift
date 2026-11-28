// logic-test
import Foundation

/// アップロードできる形に整えた写真。位置情報などのメタデータは含まない。
struct PreparedPhoto: Equatable, Sendable {
    let data: Data
    let width: Int
    let height: Int

    static let contentType = "image/jpeg"
}

enum PhotoPreparationError: Error, Equatable {
    /// 画像として読めない（壊れている、対応していない形式）
    case unreadable
    /// 縮小や圧縮をしても上限の大きさに収まらない
    case tooLarge
}
