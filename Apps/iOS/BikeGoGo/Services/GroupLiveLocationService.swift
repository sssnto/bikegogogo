import BikeGoGoCore
import Foundation

struct GroupLiveLocation: Decodable, Identifiable, Equatable {
    let user: AppUser
    let latitude: Double
    let longitude: Double
    let horizontalAccuracyMeters: Double?
    let speedMetersPerSecond: Double?
    let courseDegrees: Double?
    let capturedAt: String
    let updatedAt: String

    var id: String { user.id }
}

struct GroupMeetingPoint: Decodable, Equatable {
    let setBy: AppUser
    let latitude: Double
    let longitude: Double
    let title: String
    let horizontalAccuracyMeters: Double?
    let capturedAt: String
    let updatedAt: String
    let expiresAt: String
}

final class GroupLiveLocationService {
    private let baseURL: URL
    private let session: URLSession

    init(
        baseURL: URL? = nil,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL ?? AppConfiguration.apiBaseURL
        self.session = session
    }

    func update(
        groupID: String,
        point: RidePoint,
        accessToken: String
    ) async throws {
        let data = try JSONEncoder().encode(Self.body(for: point))
        let _: LiveLocationResponse = try await request(
            groupID: groupID,
            suffix: "live-location",
            method: "PUT",
            body: data,
            accessToken: accessToken
        )
    }

    func sendSOS(
        groupID: String,
        point: RidePoint,
        accessToken: String
    ) async throws -> Int {
        let data = try JSONEncoder().encode(Self.body(for: point))
        let response: TeamSOSResponse = try await request(
            groupID: groupID,
            suffix: "sos",
            method: "POST",
            body: data,
            accessToken: accessToken
        )
        return response.recipientCount
    }

    func locations(
        groupID: String,
        accessToken: String
    ) async throws -> [GroupLiveLocation] {
        let response: LiveLocationsResponse = try await request(
            groupID: groupID,
            suffix: "live-locations",
            method: "GET",
            accessToken: accessToken
        )
        return response.locations
    }

    func stop(
        groupID: String,
        accessToken: String
    ) async throws {
        let endpoint = endpoint(groupID: groupID, suffix: "live-location")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)
    }

    func meetingPoint(
        groupID: String,
        accessToken: String
    ) async throws -> GroupMeetingPoint? {
        let response: MeetingPointResponse = try await request(
            groupID: groupID,
            suffix: "meeting-point",
            method: "GET",
            accessToken: accessToken
        )
        return response.meetingPoint
    }

    func setMeetingPoint(
        groupID: String,
        point: RidePoint,
        title: String = "小队集合点",
        accessToken: String
    ) async throws -> GroupMeetingPoint {
        let body = MeetingPointBody(
            latitude: point.latitude,
            longitude: point.longitude,
            title: title,
            horizontalAccuracyMeters: point.horizontalAccuracyMeters,
            capturedAt: Self.timestampFormatter.string(from: point.timestamp)
        )
        let data = try JSONEncoder().encode(body)
        let response: MeetingPointResponse = try await request(
            groupID: groupID,
            suffix: "meeting-point",
            method: "PUT",
            body: data,
            accessToken: accessToken
        )
        guard let meetingPoint = response.meetingPoint else {
            throw GroupLiveLocationError.invalidResponse
        }
        return meetingPoint
    }

    func clearMeetingPoint(
        groupID: String,
        accessToken: String
    ) async throws {
        let endpoint = endpoint(groupID: groupID, suffix: "meeting-point")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)
    }

    private func request<Response: Decodable>(
        groupID: String,
        suffix: String,
        method: String,
        body: Data? = nil,
        accessToken: String
    ) async throws -> Response {
        var request = URLRequest(url: endpoint(groupID: groupID, suffix: suffix))
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func endpoint(groupID: String, suffix: String) -> URL {
        ["v1", "groups", groupID, suffix].reduce(baseURL) { url, component in
            url.appending(path: component)
        }
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GroupLiveLocationError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let serverError = try? JSONDecoder().decode(ServerErrorResponse.self, from: data)
            throw GroupLiveLocationError.server(
                code: serverError?.error ?? "request_failed",
                statusCode: httpResponse.statusCode
            )
        }
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func body(for point: RidePoint) -> LiveLocationBody {
        LiveLocationBody(
            latitude: point.latitude,
            longitude: point.longitude,
            horizontalAccuracyMeters: point.horizontalAccuracyMeters,
            speedMetersPerSecond: point.speedMetersPerSecond,
            courseDegrees: point.courseDegrees,
            capturedAt: timestampFormatter.string(from: point.timestamp)
        )
    }
}

private struct LiveLocationBody: Encodable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracyMeters: Double?
    let speedMetersPerSecond: Double?
    let courseDegrees: Double?
    let capturedAt: String
}

private struct MeetingPointBody: Encodable {
    let latitude: Double
    let longitude: Double
    let title: String
    let horizontalAccuracyMeters: Double?
    let capturedAt: String
}

private struct LiveLocationResponse: Decodable {
    let location: GroupLiveLocation
}

private struct LiveLocationsResponse: Decodable {
    let locations: [GroupLiveLocation]
}

private struct MeetingPointResponse: Decodable {
    let meetingPoint: GroupMeetingPoint?
}

private struct TeamSOSResponse: Decodable {
    let sent: Bool
    let recipientCount: Int
}

private struct ServerErrorResponse: Decodable {
    let error: String
}

private enum GroupLiveLocationError: Error {
    case invalidResponse
    case server(code: String, statusCode: Int)
}
