import Foundation

struct BoardGroup: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
}

enum GroupCreationError: Error {
    case invalidName
}
