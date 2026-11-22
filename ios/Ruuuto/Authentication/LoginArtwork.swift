import SwiftUI

struct LoginBackground: View {
    var body: some View {
        Canvas { context, size in
            var dots = Path()
            for x in stride(from: 8.0, to: size.width, by: 18.0) {
                for y in stride(from: 8.0, to: size.height, by: 18.0) {
                    dots.addEllipse(in: CGRect(x: x, y: y, width: 2, height: 2))
                }
            }
            context.fill(dots, with: .color(RuuutoPalette.soft))
        }
        .background(RuuutoPalette.ink)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

struct LoginArtwork: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            photo(.mountain)
                .rotationEffect(.degrees(-12))
                .offset(x: 9, y: 12)
            photo(.city)
                .rotationEffect(.degrees(11))
                .offset(x: 83, y: 2)
            Image(systemName: "sparkle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(RuuutoPalette.accent)
                .offset(x: 77)
        }
        .frame(width: 164, height: 102, alignment: .topLeading)
        .padding(.trailing, 4)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func photo(_ scene: Scene) -> some View {
        Canvas { context, size in
            var drawing = context
            drawing.scaleBy(x: size.width / 90, y: size.height / 90)
            switch scene {
            case .mountain: drawMountain(in: drawing)
            case .city: drawCity(in: drawing)
            }
        }
        .frame(width: 66, height: 65)
        .clipShape(.rect(cornerRadius: 2))
        .padding(.horizontal, 5)
        .padding(.top, 5)
        .padding(.bottom, 15)
        .background(.white, in: RoundedRectangle(cornerRadius: 5))
        .shadow(color: .black.opacity(0.45), radius: 7, y: 8)
    }

    private enum Scene {
        case mountain
        case city
    }

    private func drawMountain(in context: GraphicsContext) {
        context.fill(Path(CGRect(x: 0, y: 0, width: 90, height: 90)), with: .color(color(0x8EA8D2)))
        context.fill(Path(ellipseIn: CGRect(x: 51, y: 19, width: 24, height: 24)), with: .color(color(0xE9F0FF)))
        let peaks = polygon(from: CGPoint(x: 0, y: 66), through: [
            CGPoint(x: 22, y: 44), CGPoint(x: 32, y: 53), CGPoint(x: 47, y: 31),
            CGPoint(x: 90, y: 64), CGPoint(x: 90, y: 90), CGPoint(x: 0, y: 90)
        ])
        context.fill(peaks, with: .color(color(0x4C648E)))

        var foreground = Path()
        foreground.move(to: CGPoint(x: 0, y: 72))
        foreground.addQuadCurve(to: CGPoint(x: 39, y: 71), control: CGPoint(x: 23, y: 63))
        foreground.addQuadCurve(to: CGPoint(x: 90, y: 72), control: CGPoint(x: 62, y: 79))
        foreground.addLines([CGPoint(x: 90, y: 72), CGPoint(x: 90, y: 90), CGPoint(x: 0, y: 90)])
        foreground.closeSubpath()
        context.fill(foreground, with: .color(color(0xB3C8EA)))
    }

    private func drawCity(in context: GraphicsContext) {
        context.fill(Path(CGRect(x: 0, y: 0, width: 90, height: 90)), with: .color(color(0xB7CAEA)))
        let skyline = buildings([0, 13, 27, 42, 62, 75, 90], heights: [58, 41, 61, 30, 60, 47])
        context.fill(skyline, with: .color(color(0x7691BD)))
        let street = buildings([0, 15, 34, 47, 68, 90], heights: [69, 60, 73, 52, 73])
        context.fill(street, with: .color(color(0x426096)))

        var windows = Path()
        for y in [61, 66] {
            windows.move(to: CGPoint(x: 50, y: y))
            windows.addLine(to: CGPoint(x: 64, y: y))
        }
        context.stroke(windows, with: .color(color(0xCADAF4)), style: StrokeStyle(lineWidth: 2, dash: [2, 3]))
    }

    private func buildings(_ edges: [Int], heights: [Int]) -> Path {
        var path = Path()
        for (bounds, roof) in zip(zip(edges, edges.dropFirst()), heights) {
            let (left, right) = bounds
            path.addRect(CGRect(x: left, y: roof, width: right - left, height: 90 - roof))
        }
        return path
    }

    private func polygon(from start: CGPoint, through points: [CGPoint]) -> Path {
        var path = Path()
        path.addLines([start] + points)
        path.closeSubpath()
        return path
    }

    private func color(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 255) / 255,
            green: Double((hex >> 8) & 255) / 255,
            blue: Double(hex & 255) / 255
        )
    }
}
