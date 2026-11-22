import Foundation

struct CurrentBoard: Identifiable, Equatable, Sendable {
    let id: UUID
    let groupID: UUID
    let topic: String
    let opensAt: Date
    let closesAt: Date
}

enum CurrentBoardLoadError: Error {
    case noActiveBoard
}
