import Foundation
import Supabase

enum GroupDirectoryAPI {
    static func list(client: SupabaseClient) async throws -> [BoardGroup] {
        let groups: [BoardGroupDTO] = try await client
            .rpc("ruuuto_list_groups")
            .execute()
            .value
        return groups.map(\.model)
    }
}

struct BoardGroupDTO: Decodable {
    let id: UUID
    let name: String

    var model: BoardGroup { BoardGroup(id: id, name: name) }
}
