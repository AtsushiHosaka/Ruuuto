import SwiftUI

extension View {
    /// 締切からの経過に応じて、古いポスターのように黄ばませる（RCNO-28）。closedAt が nil なら何もしない。
    /// 長押しのプレビューと「大きく見る」には使わない（元の写真を確かめられるようにする）。
    func fadedBoard(closedAt: Date?, now: Date = Date()) -> some View {
        modifier(FadedBoardModifier(strength: BoardFade.strength(closedAt: closedAt, now: now)))
    }
}

private struct FadedBoardModifier: ViewModifier {
    let strength: Double

    func body(content: Content) -> some View {
        if strength <= 0 {
            content
        } else {
            let look = BoardFade.look(strength: strength)
            content
                .saturation(look.saturation)
                .contrast(look.contrast)
                .brightness(look.brightness)
                .colorMultiply(Color(red: look.tint.red, green: look.tint.green, blue: look.tint.blue))
        }
    }
}
