import SwiftUI

struct LoginArtwork: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(RuuutoPalette.soft.opacity(0.4))
            .overlay {
                Canvas { context, size in
                    var dots = Path()
                    for x in stride(from: 9.0, to: size.width, by: 18.0) {
                        for y in stride(from: 9.0, to: size.height, by: 18.0) {
                            dots.addEllipse(in: CGRect(x: x, y: y, width: 2, height: 2))
                        }
                    }
                    context.fill(dots, with: .color(RuuutoPalette.muted.opacity(0.3)))
                }
            }
            .overlay {
                ZStack {
                    photoTile(tint: RuuutoPalette.line, rotation: -11)
                        .offset(x: -38, y: 3)
                    photoTile(tint: RuuutoPalette.accent, rotation: 10)
                        .offset(x: 37, y: 7)

                    Image(systemName: "star.fill")
                        .font(.system(size: 31, weight: .semibold))
                        .foregroundStyle(RuuutoPalette.accent)
                        .shadow(color: RuuutoPalette.ink.opacity(0.35), radius: 3, y: 2)
                        .rotationEffect(.degrees(14))
                        .offset(x: 88, y: -40)
                }
            }
            .frame(height: 144)
            .accessibilityHidden(true)
    }

    private func photoTile(tint: Color, rotation: Double) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(tint)
            .frame(width: 70, height: 61)
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .padding(.bottom, 16)
            .background(.white, in: RoundedRectangle(cornerRadius: 6))
            .shadow(color: RuuutoPalette.ink.opacity(0.45), radius: 7, y: 5)
            .rotationEffect(.degrees(rotation))
    }
}
