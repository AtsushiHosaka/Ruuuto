// logic-test
import CoreGraphics
import Foundation

/// 保存された配置（x, y, rotation, scale）を画面上の位置に変える。
///
/// 座標の単位はボード担当（RCNO-17）とデザインでまだ決まっていない（RCNO-27 のマイグレーションの注記）。
/// 決まるまでは次の仮の決まりで表示し、決まったらこのファイルだけを直す。
/// - x, y は項目の中心。ボードの幅を1とした割合（y も幅を1として測る）
/// - ボードの縦横比は高さ / 幅 = `aspect`
/// - 写真は scale 1 のとき幅 `photoBaseWidth`、装飾の文字とスタンプは基準の大きさ `decorationBaseSize`
/// - rotation は度、時計回り
/// - 一度も動かしていない写真（x = y = rotation = 0、scale = 1）は、投稿順に2列で並べる
enum BoardGeometry {
    static let aspect: Double = 4.0 / 3.0
    static let photoBaseWidth: Double = 0.4
    static let decorationBaseSize: Double = 0.08

    static func isUnplaced(_ p: BoardPlacement) -> Bool {
        p.x == 0 && p.y == 0 && p.rotation == 0 && p.scale == 1
    }

    /// 描く順番: レイヤーの昇順、同じレイヤーは z_index の昇順（RCNO-19）
    static func drawOrder(_ a: BoardPlacement, _ b: BoardPlacement) -> Bool {
        (a.layer, a.zIndex) < (b.layer, b.zIndex)
    }

    /// ボードの表示の大きさ。幅に合わせ、高さは縦横比で決める
    static func boardSize(width: CGFloat) -> CGSize {
        CGSize(width: width, height: width * aspect)
    }

    /// 項目の中心。unplacedIndex は一度も動かしていない写真の中での順番
    static func center(of p: BoardPlacement, unplacedIndex: Int?, boardWidth: CGFloat) -> CGPoint {
        if let i = unplacedIndex {
            let column = Double(i % 2), row = Double(i / 2)
            return CGPoint(x: (0.27 + 0.46 * column) * boardWidth, y: (0.25 + 0.42 * row) * boardWidth)
        }
        return CGPoint(x: p.x * boardWidth, y: p.y * boardWidth)
    }

    /// 写真の表示の大きさ。幅と高さが分からない写真は正方形にする
    static func photoSize(width: Int?, height: Int?, scale: Double, boardWidth: CGFloat) -> CGSize {
        let w = photoBaseWidth * scale * boardWidth
        guard let width, let height, width > 0, height > 0 else { return CGSize(width: w, height: w) }
        return CGSize(width: w, height: w * Double(height) / Double(width))
    }
}
