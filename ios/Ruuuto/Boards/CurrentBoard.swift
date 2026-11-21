import Foundation

struct CurrentBoard: Identifiable, Equatable, Sendable {
    let id: UUID
    let groupID: UUID
    let topic: String
    let opensAt: Date
    let closesAt: Date
}

enum CurrentBoardState: Equatable, Sendable {
    case idle
    case loading
    case loaded(CurrentBoard)
    case failed(String)
}
