import Foundation
import Supabase

enum BoardDecorationAPI {
    static func addText(
        client: SupabaseClient,
        decorationID: UUID,
        boardID: UUID,
        text: String,
        x: Double,
        y: Double
    ) async throws -> BoardTextDecoration {
        do {
            let decoration: BoardDecorationDTO = try await client
                .rpc(
                    "ruuuto_add_decoration",
                    params: AddTextParameters(
                        decorationID: decorationID,
                        boardID: boardID,
                        kind: "text",
                        content: TextContent(text: text, color: "#6E9BF2"),
                        x: x,
                        y: y,
                        rotation: 0,
                        scale: 1
                    )
                )
                .execute()
                .value
            guard let model = decoration.textModel else {
                throw BoardDecorationEditingError.invalidContent
            }
            return model
        } catch let error as PostgrestError {
            throw mapped(error) ?? error
        } catch let error as HTTPError where [401, 403].contains(error.response.statusCode) {
            throw BoardDecorationEditingError.forbidden
        }
    }

    static func addPen(
        client: SupabaseClient,
        decorationID: UUID,
        boardID: UUID,
        points: [BoardPenPoint]
    ) async throws -> BoardPenDecoration {
        do {
            let decoration: BoardDecorationDTO = try await client
                .rpc(
                    "ruuuto_add_decoration",
                    params: AddPenParameters(
                        decorationID: decorationID,
                        boardID: boardID,
                        kind: "pen",
                        content: PenContent(
                            strokes: [
                                PenStrokeContent(
                                    points: points.map { [$0.x, $0.y] },
                                    color: "#6E9BF2",
                                    width: 4
                                )
                            ]
                        ),
                        x: 0,
                        y: 0,
                        rotation: 0,
                        scale: 1
                    )
                )
                .execute()
                .value
            guard let model = decoration.penModel else {
                throw BoardDecorationEditingError.invalidContent
            }
            return model
        } catch let error as PostgrestError {
            throw mapped(error) ?? error
        } catch let error as HTTPError where [401, 403].contains(error.response.statusCode) {
            throw BoardDecorationEditingError.forbidden
        }
    }

    private static func mapped(_ error: PostgrestError) -> BoardDecorationEditingError? {
        switch error.code {
        case "42501", "PGRST301", "PGRST302", "PGRST303": .forbidden
        case "RC002": .closedBoard
        case "RC009": .duplicateID
        case "RC014": .invalidContent
        default: nil
        }
    }
}

private struct AddTextParameters: Encodable {
    let decorationID: UUID
    let boardID: UUID
    let kind: String
    let content: TextContent
    let x: Double
    let y: Double
    let rotation: Double
    let scale: Double

    private enum CodingKeys: String, CodingKey {
        case decorationID = "p_decoration_id"
        case boardID = "p_board_id"
        case kind = "p_kind"
        case content = "p_content"
        case x = "p_x"
        case y = "p_y"
        case rotation = "p_rotation"
        case scale = "p_scale"
    }
}

private struct TextContent: Encodable {
    let text: String
    let color: String
}

private struct AddPenParameters: Encodable {
    let decorationID: UUID
    let boardID: UUID
    let kind: String
    let content: PenContent
    let x: Double
    let y: Double
    let rotation: Double
    let scale: Double

    private enum CodingKeys: String, CodingKey {
        case decorationID = "p_decoration_id"
        case boardID = "p_board_id"
        case kind = "p_kind"
        case content = "p_content"
        case x = "p_x"
        case y = "p_y"
        case rotation = "p_rotation"
        case scale = "p_scale"
    }
}

private struct PenContent: Encodable {
    let strokes: [PenStrokeContent]
}

private struct PenStrokeContent: Encodable {
    let points: [[Double]]
    let color: String
    let width: Double
}

struct BoardDecorationDTO: Decodable, Sendable {
    let id: UUID
    let boardID: UUID
    let createdBy: UUID
    let kind: String
    let content: BoardDecorationContentDTO
    let x: Double
    let y: Double
    let rotation: Double
    let scale: Double
    let layer: Int
    let zIndex: Int
    let revision: Int64

    private enum CodingKeys: String, CodingKey {
        case id, kind, content, x, y, rotation, scale, layer, revision
        case boardID = "board_id"
        case createdBy = "created_by"
        case zIndex = "z_index"
    }

    var textModel: BoardTextDecoration? {
        guard kind == "text", let text = content.text else { return nil }
        return BoardTextDecoration(
            id: id,
            boardID: boardID,
            createdBy: createdBy,
            text: text,
            colorHex: content.color ?? "#6E9BF2",
            x: x,
            y: y,
            rotation: rotation,
            scale: scale,
            layer: layer,
            zIndex: zIndex,
            revision: revision
        )
    }

    var penModel: BoardPenDecoration? {
        guard kind == "pen", let strokes = content.strokes else { return nil }
        let models = strokes.compactMap(\.model)
        guard !models.isEmpty else { return nil }
        return BoardPenDecoration(
            id: id,
            boardID: boardID,
            createdBy: createdBy,
            strokes: models,
            x: x,
            y: y,
            rotation: rotation,
            scale: scale,
            layer: layer,
            zIndex: zIndex,
            revision: revision
        )
    }
}

struct BoardDecorationContentDTO: Decodable, Sendable {
    let text: String?
    let color: String?
    let strokes: [BoardPenStrokeDTO]?
}

struct BoardPenStrokeDTO: Decodable, Sendable {
    let points: [[Double]]
    let color: String?
    let width: Double?

    var model: BoardPenStroke? {
        let points = points.compactMap { point -> BoardPenPoint? in
            guard point.count >= 2 else { return nil }
            return BoardPenPoint(x: point[0], y: point[1])
        }
        guard points.count >= 2 else { return nil }
        return BoardPenStroke(
            points: points,
            colorHex: color ?? "#6E9BF2",
            width: min(max(width ?? 4, 1), 24)
        )
    }
}
