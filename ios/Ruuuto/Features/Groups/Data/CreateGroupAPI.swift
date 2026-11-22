import Foundation
import Supabase

enum CreateGroupAPI {
    static func create(client: SupabaseClient, name: String, requestID: UUID) async throws -> BoardGroup {
        do {
            let group: BoardGroupDTO = try await client
                .rpc("ruuuto_create_group", params: ["p_name": name, "p_request_id": requestID.uuidString])
                .execute()
                .value
            return group.model
        } catch let error as PostgrestError where error.code == "RC006" {
            throw GroupCreationError.invalidName
        }
    }
}
