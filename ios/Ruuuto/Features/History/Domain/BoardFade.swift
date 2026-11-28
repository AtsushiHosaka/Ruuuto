// logic-test
import Foundation

/// 日がたったボードの退色（RCNO-28、2026-11-28 ルートが決定）
///
/// - 起点はボードの締切（closes_at）。開催中のボードは退色しない
/// - 強さは経過日数の平方根に比例させ、締切から182日（半年）で最大の1になる。以後は1のまま
///   目安: 1週間 0.20 / 1か月 0.41 / 3か月 0.71 / 半年 1.00
/// - 保存した画像と配置は変えず、表示だけを変える。端末の言語や地域に関係なく、同じ締切と時刻から同じ値になる
enum BoardFade {
    static let fullFadeDays: Double = 182

    static func strength(closedAt: Date?, now: Date) -> Double {
        guard let closedAt else { return 0 }
        let days = now.timeIntervalSince(closedAt) / 86_400
        guard days > 0 else { return 0 }
        return min(1, (days / fullFadeDays).squareRoot())
    }

    /// 強さごとの色の変え方。最大でも写真の内容は分かる程度にとどめる
    struct Look: Equatable, Sendable {
        let saturation: Double
        /// 掛け合わせる色（赤・緑・青）。青を落として黄ばませる
        let tint: (red: Double, green: Double, blue: Double)
        let brightness: Double
        let contrast: Double

        static func == (a: Look, b: Look) -> Bool {
            a.saturation == b.saturation && a.tint == b.tint && a.brightness == b.brightness && a.contrast == b.contrast
        }
    }

    static func look(strength s: Double) -> Look {
        let s = max(0, min(1, s))
        return Look(
            saturation: 1 - 0.55 * s,
            tint: (red: 1, green: 1 - 0.06 * s, blue: 1 - 0.32 * s),
            brightness: 0.05 * s,
            contrast: 1 - 0.18 * s
        )
    }
}
