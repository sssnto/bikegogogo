import BikeGoGoCore
import Foundation

struct RideCloudClient {
    var baseURL: URL = AppConfiguration.apiBaseURL
    var session: URLSession = .shared

    func synchronize(
        localRides: [RideSession],
        accessToken: String
    ) async throws -> [RideSession] {
        for ride in localRides where ride.state == .finished {
            let body = try encoder.encode(ride)
            let _: RideResponse = try await request(
                path: ["v1", "rides", ride.id.uuidString.lowercased()],
                method: "PUT",
                body: body,
                accessToken: accessToken
            )
        }

        let response: RidesResponse = try await request(
            path: ["v1", "rides"],
            accessToken: accessToken
        )
        return response.rides.sorted { $0.startedAt > $1.startedAt }
    }

    func delete(rideID: UUID, accessToken: String) async throws {
        let endpoint = ["v1", "rides", rideID.uuidString.lowercased()].reduce(baseURL) {
            url,
            component in url.appending(path: component)
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RideCloudError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let serverError = try? JSONDecoder().decode(RideServerError.self, from: data)
            throw RideCloudError.server(
                message: serverError?.message ?? "HTTP \(httpResponse.statusCode)"
            )
        }
    }

    private func request<Response: Decodable>(
        path: [String],
        method: String = "GET",
        body: Data? = nil,
        accessToken: String
    ) async throws -> Response {
        let endpoint = path.reduce(baseURL) { url, component in
            url.appending(path: component)
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RideCloudError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let serverError = try? JSONDecoder().decode(RideServerError.self, from: data)
            throw RideCloudError.server(
                message: serverError?.message ?? "HTTP \(httpResponse.statusCode)"
            )
        }
        return try decoder.decode(Response.self, from: data)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct RidesResponse: Decodable {
    let rides: [RideSession]
}

private struct RideResponse: Decodable {
    let ride: RideSession
}

private struct RideServerError: Decodable {
    let message: String
}

private enum RideCloudError: LocalizedError {
    case invalidResponse
    case server(message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "服务器返回了无法识别的响应。"
        case let .server(message):
            message
        }
    }
}
