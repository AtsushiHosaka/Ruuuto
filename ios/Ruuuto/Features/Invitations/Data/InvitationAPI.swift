import Foundation
import Supabase

struct InvitationAPI: Sendable {
    let client: SupabaseClient

    func issue(groupID: UUID) async throws -> String {
        _ = try await client.auth.session
        try Task.checkCancellation()
        let response: IssuedInvitation = try await client
            .rpc("ruuuto_issue_invitation", params: IssueParameters(groupID: groupID))
            .execute()
            .value
        return response.token
    }

    func accept(token: String) async throws -> InvitationAcceptance {
        _ = try await client.auth.session
        try Task.checkCancellation()
        do {
            let response: AcceptedInvitation = try await client
                .rpc("ruuuto_accept_invitation", params: AcceptParameters(token: token))
                .execute()
                .value
            return InvitationAcceptance(
                groupID: response.groupID,
                membership: response.joined ? .joined : .alreadyMember
            )
        } catch let error as PostgrestError {
            switch error.code {
            case "RC003": throw InvitationJoinError.invalid
            case "RC004": throw InvitationJoinError.expired
            default: throw error
            }
        }
    }

    private struct IssueParameters: Encodable {
        let groupID: UUID

        enum CodingKeys: String, CodingKey {
            case groupID = "p_group_id"
        }
    }

    private struct AcceptParameters: Encodable {
        let token: String

        enum CodingKeys: String, CodingKey {
            case token = "p_token"
        }
    }

    private struct IssuedInvitation: Decodable {
        let token: String
    }

    private struct AcceptedInvitation: Decodable {
        let groupID: UUID
        let joined: Bool

        enum CodingKeys: String, CodingKey {
            case groupID = "group_id"
            case joined
        }
    }
}
