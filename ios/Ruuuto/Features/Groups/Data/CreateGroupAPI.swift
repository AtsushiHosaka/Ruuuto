import Foundation
import Supabase

enum CreateGroupAPI {
    static func create(client: SupabaseClient, name: String, requestID: UUID) async throws -> BoardGroup {
        let group: BoardGroupDTO = try await client
            .rpc("ruuuto_create_group", params: ["p_name": name, "p_request_id": requestID.uuidString])
            .execute()
            .value
        return group.model
    }
}
