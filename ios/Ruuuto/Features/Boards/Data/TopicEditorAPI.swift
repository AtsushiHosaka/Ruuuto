import Foundation
import Supabase

enum TopicEditorAPI {
    static func save(client: SupabaseClient, boardID: UUID, topic: String) async throws {
        do {
            try await client
                .rpc("ruuuto_save_topic", params: Parameters(boardID: boardID, topic: topic))
                .execute()
        } catch let error as PostgrestError {
            switch error.code {
            case "42501", "PGRST301", "PGRST302", "PGRST303":
                throw TopicSaveError.forbidden
            case "RC001":
                throw TopicSaveError.invalidTopic
            case "RC002":
                throw TopicSaveError.closedBoard
            default:
                throw error
            }
        } catch let error as HTTPError where [401, 403].contains(error.response.statusCode) {
            throw TopicSaveError.forbidden
        }
    }

    private struct Parameters: Encodable {
        let boardID: UUID
        let topic: String

        private enum CodingKeys: String, CodingKey {
            case boardID = "p_board_id"
            case topic = "p_topic"
        }
    }
}
