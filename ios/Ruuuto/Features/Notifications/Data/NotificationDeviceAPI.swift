import Foundation
import Supabase

enum NotificationDeviceAPI {
    static func synchronize(
        client: SupabaseClient,
        installationID: UUID,
        registration: NotificationDeviceRegistration
    ) async throws {
        try await client
            .rpc("ruuuto_sync_device", params: DeviceParameters(installationID: installationID, registration: registration))
            .execute()
    }

    static func decodeDestination(_ data: Data) -> NotificationDestination? {
        guard let payload = try? JSONDecoder().decode(DestinationPayload.self, from: data) else { return nil }
        return NotificationDestination(groupID: payload.groupID, boardID: payload.boardID)
    }

    private struct DeviceParameters: Encodable {
        let installationID: UUID
        let registration: NotificationDeviceRegistration

        private enum CodingKeys: String, CodingKey {
            case installationID = "p_installation_id"
            case apnsToken = "p_apns_token"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(installationID, forKey: .installationID)
            switch registration {
            case .registered(let token):
                let hexadecimal = token.map { String(format: "%02x", $0) }.joined()
                try container.encode(hexadecimal, forKey: .apnsToken)
            case .unregistered:
                try container.encodeNil(forKey: .apnsToken)
            }
        }
    }

    private struct DestinationPayload: Decodable {
        let groupID: UUID
        let boardID: UUID

        private enum CodingKeys: String, CodingKey {
            case groupID = "group_id"
            case boardID = "board_id"
        }
    }
}
