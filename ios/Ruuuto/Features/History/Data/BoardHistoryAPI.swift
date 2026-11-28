import Foundation
import Supabase

/// 月別の履歴とボードの読み取り（RCNO-43、RCNO-19）
enum BoardHistoryAPI {
    static func history(client: SupabaseClient, groupID: UUID, month: BoardMonth) async throws -> [BoardSummary] {
        let boards: [BoardSummaryDTO] = try await client
            .rpc("ruuuto_board_history", params: HistoryParams(groupID: groupID, year: month.year, month: month.month))
            .execute()
            .value
        return try boards.map { try $0.model() }
    }

    static func snapshot(client: SupabaseClient, boardID: UUID) async throws -> BoardSnapshot {
        let snapshot: SnapshotDTO = try await client
            .rpc("ruuuto_board_snapshot", params: ["p_board_id": boardID])
            .execute()
            .value
        return try snapshot.model()
    }
}

/// 非公開の photos バケットから画像を取得し、メモリに置いておく。ボード、カレンダー、マップで共有する。
actor PhotoImageCache {
    private let client: SupabaseClient
    private var images: [String: Data] = [:]
    private var order: [String] = []
    private let limit = 120

    init(client: SupabaseClient) { self.client = client }

    func data(for storagePath: String) async throws -> Data {
        if let data = images[storagePath] { return data }
        let data = try await client.storage.from(PhotoPostAPI.bucket).download(path: storagePath)
        images[storagePath] = data
        order.append(storagePath)
        if order.count > limit { images[order.removeFirst()] = nil }
        return data
    }

    /// 取り下げた写真を消す
    func remove(_ storagePath: String) {
        images[storagePath] = nil
        order.removeAll { $0 == storagePath }
    }
}

private struct HistoryParams: Encodable, Sendable {
    let groupID: UUID
    let year: Int
    let month: Int

    private enum CodingKeys: String, CodingKey {
        case groupID = "p_group_id"
        case year = "p_year"
        case month = "p_month"
    }
}

/// サーバーの日時（UTC、"2026-11-16T00:00:00Z"）。小数秒あり・なしの両方を読む。
struct ServerDate: Decodable, Sendable {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let wholeSeconds = Date.ISO8601FormatStyle()

    let value: Date

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let date = (try? Self.fractional.parse(text)) ?? (try? Self.wholeSeconds.parse(text)) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected an ISO 8601 timestamp.")
        }
        value = date
    }
}

struct BoardSummaryDTO: Decodable, Sendable {
    let id: UUID
    let topic: String
    let topicTexts: [String: String]?
    let opensAt: ServerDate
    let closesAt: ServerDate
    let status: String
    let photoCount: Int?
    let previewPaths: [String]?

    private enum CodingKeys: String, CodingKey {
        case id, topic, status
        case topicTexts = "topic_texts"
        case opensAt = "opens_at"
        case closesAt = "closes_at"
        case photoCount = "photo_count"
        case previewPaths = "preview_paths"
    }

    func model() throws -> BoardSummary {
        BoardSummary(
            id: id, topic: topic, topicTexts: topicTexts ?? [:],
            opensAt: opensAt.value, closesAt: closesAt.value, isOpen: status == "open",
            photoCount: photoCount ?? 0, previewPaths: previewPaths ?? []
        )
    }
}

private struct PlacementFields: Decodable, Sendable {
    let x: Double
    let y: Double
    let rotation: Double
    let scale: Double
    let layer: Int?
    let zIndex: Int

    private enum CodingKeys: String, CodingKey {
        case x, y, rotation, scale, layer
        case zIndex = "z_index"
    }

    /// layer がない（RCNO-19 のレイヤー追加前の形）ときは、写真 1・装飾 2 として扱う
    func model(defaultLayer: Int) -> BoardPlacement {
        BoardPlacement(x: x, y: y, rotation: rotation, scale: scale, layer: layer ?? defaultLayer, zIndex: zIndex)
    }
}

private struct SnapshotDTO: Decodable, Sendable {
    struct Photo: Decodable, Sendable {
        let id: UUID
        let postedBy: UUID
        let storagePath: String
        let city: String?
        let width: Int?
        let height: Int?

        private enum CodingKeys: String, CodingKey {
            case id, city, width, height
            case postedBy = "posted_by"
            case storagePath = "storage_path"
        }
    }

    struct Decoration: Decodable, Sendable {
        let id: UUID
        let createdBy: UUID
        let kind: String
        let content: AnyJSON

        private enum CodingKeys: String, CodingKey {
            case id, kind, content
            case createdBy = "created_by"
        }
    }

    struct Item<Fields: Decodable & Sendable>: Decodable, Sendable {
        let fields: Fields
        let placement: PlacementFields

        init(from decoder: Decoder) throws {
            fields = try Fields(from: decoder)
            placement = try PlacementFields(from: decoder)
        }
    }

    let board: BoardSummaryDTO
    let photos: [Item<Photo>]
    let decorations: [Item<Decoration>]

    func model() throws -> BoardSnapshot {
        BoardSnapshot(
            board: try board.model(),
            photos: photos.map { item in
                let p = item.fields
                return BoardPhoto(id: p.id, postedBy: p.postedBy, storagePath: p.storagePath, city: p.city,
                                  width: p.width, height: p.height, placement: item.placement.model(defaultLayer: 1))
            },
            decorations: decorations.map { item in
                let d = item.fields
                return BoardDecoration(id: d.id, createdBy: d.createdBy, content: Self.content(kind: d.kind, json: d.content),
                                       placement: item.placement.model(defaultLayer: 2))
            }
        )
    }

    /// JSON の数は整数と小数の両方で届く
    static func number(_ json: AnyJSON) -> Double? {
        switch json {
        case .integer(let value): Double(value)
        case .double(let value): value
        default: nil
        }
    }

    /// 装飾の content（RCNO-27 の推奨の形）。足りない項目は既定値にし、読めない種類は表示しない。
    static func content(kind: String, json: AnyJSON) -> BoardDecoration.Content {
        guard case .object(let object) = json else { return .unknown }
        switch kind {
        case "text":
            guard case .string(let text) = object["text"] else { return .unknown }
            return .text(text, colorHex: object["color"]?.stringValue)
        case "stamp":
            guard case .string(let id) = object["stamp_id"] else { return .unknown }
            return .stamp(id)
        case "pen":
            guard case .array(let strokes) = object["strokes"] else { return .unknown }
            return .pen(strokes.compactMap { stroke in
                guard case .object(let s) = stroke, case .array(let points) = s["points"] else { return nil }
                let pts: [[Double]] = points.compactMap { point in
                    guard case .array(let xy) = point, xy.count >= 2,
                          let x = number(xy[0]), let y = number(xy[1]) else { return nil }
                    return [x, y]
                }
                return BoardDecoration.Stroke(points: pts, colorHex: s["color"]?.stringValue,
                                              width: s["width"].flatMap(number) ?? 4)
            })
        default:
            return .unknown
        }
    }
}
