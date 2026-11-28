import Foundation
import Supabase

enum BoardPhotoSyncAPI {
    static func events(client: SupabaseClient, boardID: UUID) -> AsyncStream<BoardPhotoSyncEvent> {
        AsyncStream { continuation in
            let producer = Task {
                while !Task.isCancelled {
                    continuation.yield(.connecting)

                    let channel = client.channel("board:\(boardID.uuidString.lowercased())") { config in
                        config.isPrivate = true
                    }
                    let statuses = channel.statusChange
                    let savedPhotos = channel.broadcastStream(event: "photo_saved")
                    let withdrawnPhotos = channel.broadcastStream(event: "photo_withdrawn")

                    do {
                        try await withThrowingTaskGroup(of: Void.self) { group in
                            group.addTask {
                                for await status in statuses {
                                    guard !Task.isCancelled else { return }
                                    switch status {
                                    case .subscribing:
                                        continuation.yield(.connecting)
                                    case .subscribed:
                                        continuation.yield(.connected)
                                    case .unsubscribed, .unsubscribing:
                                        break
                                    }
                                }
                            }
                            group.addTask {
                                for await message in savedPhotos {
                                    guard !Task.isCancelled else { return }
                                    do {
                                        let photo: SavedPhotoDTO = try decodePayload(from: message)
                                        continuation.yield(.photoSaved(photo.change))
                                    } catch {
                                        continuation.yield(.snapshotRequired)
                                    }
                                }
                            }
                            group.addTask {
                                for await message in withdrawnPhotos {
                                    guard !Task.isCancelled else { return }
                                    do {
                                        let photo: WithdrawnPhotoDTO = try decodePayload(from: message)
                                        continuation.yield(
                                            .photoWithdrawn(boardID: photo.boardID, photoID: photo.id)
                                        )
                                    } catch {
                                        continuation.yield(.snapshotRequired)
                                    }
                                }
                            }

                            try await channel.subscribeWithError()
                            try await group.waitForAll()
                        }
                    } catch is CancellationError {
                        await client.removeChannel(channel)
                        break
                    } catch {
                        continuation.yield(.connectionFailed)
                    }

                    await client.removeChannel(channel)
                    guard !Task.isCancelled else { break }
                    do {
                        try await Task.sleep(for: .seconds(2))
                    } catch {
                        break
                    }
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                producer.cancel()
            }
        }
    }

    private static func decodePayload<Value: Decodable>(from message: JSONObject) throws -> Value {
        guard let payload = message["payload"]?.objectValue else {
            throw PayloadError.missingPayload
        }
        let data = try JSONEncoder().encode(payload)
        return try JSONDecoder().decode(Value.self, from: data)
    }
}

private enum PayloadError: Error {
    case missingPayload
}

private struct SavedPhotoDTO: Decodable, Sendable {
    let id: UUID
    let boardID: UUID
    let x: Double
    let y: Double
    let rotation: Double
    let scale: Double
    let layer: Int?
    let zIndex: Int
    let revision: Int64

    private enum CodingKeys: String, CodingKey {
        case id, x, y, rotation, scale, layer, revision
        case boardID = "board_id"
        case zIndex = "z_index"
    }

    var change: BoardPhotoSavedChange {
        BoardPhotoSavedChange(
            id: id,
            boardID: boardID,
            x: x,
            y: y,
            rotation: rotation,
            scale: scale,
            layer: layer ?? 1,
            zIndex: zIndex,
            revision: revision
        )
    }
}

private struct WithdrawnPhotoDTO: Decodable, Sendable {
    let id: UUID
    let boardID: UUID

    private enum CodingKeys: String, CodingKey {
        case id
        case boardID = "board_id"
    }
}
