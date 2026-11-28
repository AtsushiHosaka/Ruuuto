import Foundation

enum BoardCoordinateConverter {
    static func normalized(_ value: CGFloat, length: CGFloat) -> Double {
        guard length > 0 else { return 0 }
        return min(max(Double(value / length), 0), 1)
    }

    static func screen(_ value: Double, length: CGFloat) -> CGFloat {
        guard value >= 0, value <= 1 else { return CGFloat(value) }
        return CGFloat(value) * length
    }
}
