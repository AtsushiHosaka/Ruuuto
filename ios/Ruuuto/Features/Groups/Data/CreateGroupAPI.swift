import Supabase

enum CreateGroupAPI {
    static func create(client: SupabaseClient, name: String) async throws -> BoardGroup {
        let group: BoardGroupDTO = try await client
            .rpc("ruuuto_create_group", params: ["p_name": name])
            .execute()
            .value
        return group.model
    }
}
