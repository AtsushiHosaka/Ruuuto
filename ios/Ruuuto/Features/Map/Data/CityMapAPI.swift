import Foundation
import Supabase

/// 都市別の写真数と写真一覧（RCNO-43）
enum CityMapAPI {
    static func cities(client: SupabaseClient, boardID: UUID) async throws -> [CityCount] {
        let rows: [CityCountDTO] = try await client
            .rpc("ruuuto_board_cities", params: ["p_board_id": boardID])
            .execute()
            .value
        return rows.map { CityCount(cityID: $0.city, photoCount: $0.photoCount) }
    }

    static func photos(client: SupabaseClient, boardID: UUID, cityID: String) async throws -> [CityPhoto] {
        let rows: [CityPhotoDTO] = try await client
            .rpc("ruuuto_city_photos", params: CityPhotosParams(boardID: boardID, city: cityID))
            .execute()
            .value
        return rows.map {
            CityPhoto(id: $0.id, storagePath: $0.storagePath, postedBy: $0.postedBy, displayName: $0.displayName,
                      postedAt: $0.postedAt.value, width: $0.width, height: $0.height)
        }
    }
}

private struct CityPhotosParams: Encodable, Sendable {
    let boardID: UUID
    let city: String

    private enum CodingKeys: String, CodingKey {
        case boardID = "p_board_id"
        case city = "p_city"
    }
}

private struct CityCountDTO: Decodable, Sendable {
    let city: String
    let photoCount: Int

    private enum CodingKeys: String, CodingKey {
        case city
        case photoCount = "photo_count"
    }
}

private struct CityPhotoDTO: Decodable, Sendable {
    let id: UUID
    let storagePath: String
    let postedBy: UUID
    let displayName: String
    let postedAt: ServerDate
    let width: Int?
    let height: Int?

    private enum CodingKeys: String, CodingKey {
        case id, width, height
        case storagePath = "storage_path"
        case postedBy = "posted_by"
        case displayName = "display_name"
        case postedAt = "posted_at"
    }
}
