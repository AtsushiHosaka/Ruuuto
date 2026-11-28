import Foundation
import Supabase

enum BoardPhotoEditingAPI {
    static func loadSnapshot(client: SupabaseClient, boardID: UUID) async throws -> BoardSnapshot {
        do {
            let snapshot: SnapshotDTO = try await client
                .rpc("ruuuto_board_snapshot", params: BoardParameters(boardID: boardID))
                .execute()
                .value

            var photos: [BoardPhoto] = []
            photos.reserveCapacity(snapshot.photos.count)
            for photo in snapshot.photos {
                let imageURL = try await client.storage
                    .from(photo.bucket)
                    .createSignedURL(path: photo.storagePath, expiresIn: 60 * 60)
                photos.append(photo.model(imageURL: imageURL))
            }

            return BoardSnapshot(
                boardID: snapshot.board.id,
                isOpen: snapshot.board.status == "open",
                closesAt: snapshot.board.closesAt.value,
                photos: photos,
                textDecorations: snapshot.decorations.compactMap(\.textModel),
                penDecorations: snapshot.decorations.compactMap(\.penModel),
                stampDecorations: snapshot.decorations.compactMap(\.stampModel)
            )
        } catch let error as PostgrestError {
            throw mapped(error) ?? error
        } catch let error as HTTPError where [401, 403].contains(error.response.statusCode) {
            throw BoardPhotoEditingError.forbidden
        }
    }

    static func grab(client: SupabaseClient, photoID: UUID) async throws -> BoardPhotoUpdate {
        try await mutation(client: client, name: "ruuuto_grab_photo", params: PhotoParameters(photoID: photoID))
    }

    static func move(
        client: SupabaseClient,
        photoID: UUID,
        x: Double,
        y: Double,
        rotation: Double,
        scale: Double
    ) async throws -> BoardPhotoUpdate {
        try await mutation(
            client: client,
            name: "ruuuto_move_photo",
            params: MoveParameters(
                photoID: photoID,
                x: x,
                y: y,
                rotation: rotation,
                scale: scale,
                release: true
            )
        )
    }

    static func release(client: SupabaseClient, photoID: UUID) async {
        _ = try? await mutation(
            client: client,
            name: "ruuuto_release_photo",
            params: PhotoParameters(photoID: photoID)
        )
    }

    private static func mutation<Parameters: Encodable>(
        client: SupabaseClient,
        name: String,
        params: Parameters
    ) async throws -> BoardPhotoUpdate {
        do {
            let photo: PhotoDTO = try await client.rpc(name, params: params).execute().value
            return photo.update
        } catch let error as PostgrestError {
            throw mapped(error) ?? error
        } catch let error as HTTPError where [401, 403].contains(error.response.statusCode) {
            throw BoardPhotoEditingError.forbidden
        }
    }

    private static func mapped(_ error: PostgrestError) -> BoardPhotoEditingError? {
        switch error.code {
        case "42501", "PGRST301", "PGRST302", "PGRST303": .forbidden
        case "RC002": .closedBoard
        case "RC012": .lockedByAnotherParticipant
        case "RC013": .lostLock
        case "RC014": .invalidPosition
        case "RC016": .fixedBackground
        default: nil
        }
    }
}

private struct BoardParameters: Encodable {
    let boardID: UUID

    private enum CodingKeys: String, CodingKey {
        case boardID = "p_board_id"
    }
}

private struct PhotoParameters: Encodable {
    let photoID: UUID

    private enum CodingKeys: String, CodingKey {
        case photoID = "p_photo_id"
    }
}

private struct MoveParameters: Encodable {
    let photoID: UUID
    let x: Double
    let y: Double
    let rotation: Double
    let scale: Double
    let release: Bool

    private enum CodingKeys: String, CodingKey {
        case photoID = "p_photo_id"
        case x = "p_x"
        case y = "p_y"
        case rotation = "p_rotation"
        case scale = "p_scale"
        case release = "p_release"
    }
}

private struct SnapshotDTO: Decodable {
    let board: SnapshotBoardDTO
    let photos: [PhotoDTO]
    let decorations: [BoardDecorationDTO]
}

private struct SnapshotBoardDTO: Decodable {
    let id: UUID
    let closesAt: SnapshotTimestamp
    let status: String

    private enum CodingKeys: String, CodingKey {
        case id, status
        case closesAt = "closes_at"
    }
}

private struct PhotoDTO: Decodable {
    let id: UUID
    let boardID: UUID
    let postedBy: UUID
    let bucket: String
    let storagePath: String
    let city: String?
    let width: Int?
    let height: Int?
    let x: Double
    let y: Double
    let rotation: Double
    let scale: Double
    let layer: Int
    let zIndex: Int
    let revision: Int64
    let lockedBy: UUID?
    let lockExpiresAt: SnapshotTimestamp?

    private enum CodingKeys: String, CodingKey {
        case id, bucket, city, width, height, x, y, rotation, scale, layer, revision
        case boardID = "board_id"
        case postedBy = "posted_by"
        case storagePath = "storage_path"
        case zIndex = "z_index"
        case lockedBy = "locked_by"
        case lockExpiresAt = "lock_expires_at"
    }

    func model(imageURL: URL) -> BoardPhoto {
        BoardPhoto(
            id: id,
            boardID: boardID,
            postedBy: postedBy,
            imageURL: imageURL,
            city: city,
            pixelWidth: width,
            pixelHeight: height,
            x: x,
            y: y,
            rotation: rotation,
            scale: scale,
            layer: layer,
            zIndex: zIndex,
            revision: revision,
            lockedBy: lockedBy,
            lockExpiresAt: lockExpiresAt?.value
        )
    }

    var update: BoardPhotoUpdate {
        BoardPhotoUpdate(
            id: id,
            boardID: boardID,
            x: x,
            y: y,
            rotation: rotation,
            scale: scale,
            layer: layer,
            zIndex: zIndex,
            revision: revision,
            lockedBy: lockedBy,
            lockExpiresAt: lockExpiresAt?.value
        )
    }
}

private struct SnapshotTimestamp: Decodable {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let wholeSeconds = Date.ISO8601FormatStyle()

    let value: Date

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let timestamp = try container.decode(String.self)
        guard let date = (try? Self.fractional.parse(timestamp)) ?? (try? Self.wholeSeconds.parse(timestamp)) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO 8601 timestamp with an offset."
            )
        }
        value = date
    }
}
