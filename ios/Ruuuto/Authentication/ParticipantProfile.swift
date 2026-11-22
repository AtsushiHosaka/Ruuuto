import Foundation

struct ParticipantProfile: Decodable, Equatable, Sendable {
    let id: UUID
    let displayName: String

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}
