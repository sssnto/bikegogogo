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
        identity: String,
        displayName: String
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
        request.httpBody = try JSONEncoder().encode([
            "identity": identity,
            "displayName": displayName
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
