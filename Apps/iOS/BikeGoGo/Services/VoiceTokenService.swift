import Foundation

struct VoiceTokenResponse: Decodable, Equatable {
    var url: URL
    var token: String
    var roomName: String
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
}

enum VoiceTokenError: Error {
    case requestFailed
}
