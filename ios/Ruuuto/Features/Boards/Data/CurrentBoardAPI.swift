import Foundation
import Supabase

enum CurrentBoardAPI {
    static func load(client: SupabaseClient, groupID: UUID) async throws -> CurrentBoard {
        do {
            let board: CurrentBoardDTO = try await client
                .rpc("ruuuto_current_board", params: ["p_group_id": groupID])
                .execute()
                .value
            return board.model
        } catch let error as PostgrestError where error.code == "P0002" {
            throw CurrentBoardLoadError.noActiveBoard
        }
    }
}

private struct CurrentBoardDTO: Decodable {
    let id: UUID
    let groupID: UUID
    let topic: String
    let opensAt: BoardTimestamp
    let closesAt: BoardTimestamp

    private enum CodingKeys: String, CodingKey {
        case id, topic
        case groupID = "group_id"
        case opensAt = "opens_at"
        case closesAt = "closes_at"
    }

    var model: CurrentBoard {
        CurrentBoard(id: id, groupID: groupID, topic: topic, opensAt: opensAt.value, closesAt: closesAt.value)
    }
}

private struct BoardTimestamp: Decodable {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let wholeSeconds = Date.ISO8601FormatStyle()

    let value: Date

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let timestamp = try container.decode(String.self)
        // Decode the explicit Postgres UTC offset rather than inheriting the SDK's Date strategy.
        guard let date = (try? Self.fractional.parse(timestamp)) ?? (try? Self.wholeSeconds.parse(timestamp)) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected an ISO 8601 timestamp with an offset.")
        }
        self.value = date
    }
}
