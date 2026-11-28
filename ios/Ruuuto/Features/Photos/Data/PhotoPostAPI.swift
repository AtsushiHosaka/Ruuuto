import Foundation
import Supabase

/// 写真投稿の RPC と Storage（RCNO-35）
enum PhotoPostAPI {
    static let bucket = "photos"

    static func poster(client: SupabaseClient) -> PhotoPoster {
        PhotoPoster(
            begin: { photoID, boardID, city, width, height in
                try await mapErrors {
                    let photo: PhotoDTO = try await client
                        .rpc("ruuuto_begin_photo", params: BeginParams(
                            photoID: photoID, boardID: boardID, city: city, width: width, height: height
                        ))
                        .execute()
                        .value
                    return try photo.model()
                }
            },
            upload: { storagePath, data in
                try await mapErrors { () async throws -> Void in
                    _ = try await client.storage.from(bucket).upload(
                        storagePath,
                        data: data,
                        options: FileOptions(contentType: PreparedPhoto.contentType, upsert: true)
                    )
                }
            },
            finish: { photoID in
                try await mapErrors {
                    let photo: PhotoDTO = try await client
                        .rpc("ruuuto_finish_photo", params: ["p_photo_id": photoID])
                        .execute()
                        .value
                    return try photo.model()
                }
            }
        )
    }

    /// サーバーのエラーコードを PhotoPostError にする。キャンセルはそのまま伝える。
    static func mapErrors<T: Sendable>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as PostgrestError {
            throw postError(code: error.code)
        } catch let error as StorageError {
            // Storage の権限拒否は、締切後のアップロード（RCNO-27）か所属外。どちらも送り直しても通らない。
            throw error.statusCode == "403" ? PhotoPostError.forbidden : PhotoPostError.retryable
        } catch let error as PhotoPostError {
            throw error
        } catch {
            throw PhotoPostError.retryable
        }
    }

    static func postError(code: String?) -> PhotoPostError {
        switch code {
        case "RC002": .boardClosed
        case "RC010": .withdrawn
        case "42501": .forbidden
        case "RC008", "RC009": .rejected
        default: .retryable // RC007（画像が未到着）と通信の失敗
        }
    }
}

private struct BeginParams: Encodable, Sendable {
    let photoID: UUID
    let boardID: UUID
    let city: String?
    let width: Int
    let height: Int

    private enum CodingKeys: String, CodingKey {
        case photoID = "p_photo_id"
        case boardID = "p_board_id"
        case city = "p_city"
        case width = "p_width"
        case height = "p_height"
    }
}

struct PhotoDTO: Decodable, Sendable {
    let id: UUID
    let boardID: UUID
    let postedBy: UUID
    let storagePath: String
    let status: String
    let city: String?
    let width: Int?
    let height: Int?

    private enum CodingKeys: String, CodingKey {
        case id, status, city, width, height
        case boardID = "board_id"
        case postedBy = "posted_by"
        case storagePath = "storage_path"
    }

    func model() throws -> PostedPhoto {
        guard let status = PostedPhoto.Status(rawValue: status) else { throw PhotoPostError.rejected }
        return PostedPhoto(
            id: id, boardID: boardID, postedBy: postedBy, storagePath: storagePath,
            status: status, city: city, width: width, height: height
        )
    }
}
