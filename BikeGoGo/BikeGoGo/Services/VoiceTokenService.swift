import Foundation

struct VoiceTokenResponse: Decodable, Equatable {
    var url: URL
    var token: String
    var roomName: String
}

struct VoiceInvitation: Decodable, Identifiable, Equatable {
    var id: String
    var caller: AppUser
    var targetId: String
    var targetKind: String
    var targetName: String
    var createdAt: String
    var expiresAt: String

    var isGroupCall: Bool {
        targetKind == "group"
    }
}

struct VoiceTokenService {
    var baseURL: URL = AppConfiguration.apiBaseURL
    var session: URLSession = .shared

    func token(
        groupID: String,
        accessToken: String
    ) async throws -> VoiceTokenResponse {
        let endpoint = baseURL
            .appending(path: "v1")
            .appending(path: "voice")
            .appending(path: "rooms")
            .appending(path: groupID)
            .appending(path: "token")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode([
            "canPublish": true,
            "canSubscribe": true
        ])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw VoiceTokenError.requestFailed
        }

        return try JSONDecoder().decode(VoiceTokenResponse.self, from: data)
    }

    func createInvitation(
        targetID: String,
        accessToken: String
    ) async throws -> VoiceInvitation {
        let body = try JSONEncoder().encode(["targetId": targetID])
        let response: VoiceInvitationEnvelope = try await request(
            path: ["v1", "voice", "invitations"],
            method: "POST",
            body: body,
            accessToken: accessToken
        )
        return response.invitation
    }

    func pendingInvitations(accessToken: String) async throws -> [VoiceInvitation] {
        let response: VoiceInvitationsEnvelope = try await request(
            path: ["v1", "voice", "invitations"],
            method: "GET",
            accessToken: accessToken
        )
        return response.invitations
    }

    func respond(
        invitationID: String,
        action: String,
        accessToken: String
    ) async throws -> VoiceInvitation {
        let body = try JSONEncoder().encode(["action": action])
        let response: VoiceInvitationEnvelope = try await request(
            path: ["v1", "voice", "invitations", invitationID, "respond"],
            method: "POST",
            body: body,
            accessToken: accessToken
        )
        return response.invitation
    }

    func cancelInvitation(
        invitationID: String,
        accessToken: String
    ) async throws {
        let endpoint = ["v1", "voice", "invitations", invitationID].reduce(baseURL) {
            $0.appending(path: $1)
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw VoiceTokenError.requestFailed
        }
    }

    private func request<Response: Decodable>(
        path: [String],
        method: String,
        body: Data? = nil,
        accessToken: String
    ) async throws -> Response {
        let endpoint = path.reduce(baseURL) {
            $0.appending(path: $1)
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw VoiceTokenError.requestFailed
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

private struct VoiceInvitationEnvelope: Decodable {
    var invitation: VoiceInvitation
}

private struct VoiceInvitationsEnvelope: Decodable {
    var invitations: [VoiceInvitation]
}

enum VoiceTokenError: LocalizedError {
    case requestFailed

    var errorDescription: String? {
        "服务器暂时无法处理语音请求，请稍后重试。"
    }
}
