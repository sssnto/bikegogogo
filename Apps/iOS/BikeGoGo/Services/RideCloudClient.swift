import BikeGoGoCore
import Foundation

struct RideCloudClient {
    var baseURL: URL = AppConfiguration.apiBaseURL
    var session: URLSession = .shared

    func synchronize(
        localRides: [RideSession],
        accessToken: String
    ) async throws -> RideCloudSyncResult {
        let initialResponse: RidesResponse = try await request(
            path: ["v1", "rides"],
            accessToken: accessToken
        )
        let cloudRidesByID = Dictionary(
            uniqueKeysWithValues: initialResponse.rides.map { ($0.id, $0) }
        )
        let ridesToUpload = localRides.filter {
            $0.state == .finished && cloudRidesByID[$0.id] != $0
        }

        var failures: [RideCloudUploadFailure] = []
        var uploadedRideCount = 0
        for ride in ridesToUpload {
            do {
                let body = try encoder.encode(ride)
                let _: RideResponse = try await request(
                    path: ["v1", "rides", ride.id.uuidString],
                    method: "PUT",
                    body: body,
                    accessToken: accessToken
                )
                uploadedRideCount += 1
            } catch {
                failures.append(
                    RideCloudUploadFailure(
                        rideID: ride.id,
                        title: ride.title,
                        error: error
                    )
                )
            }
        }

        let response: RidesResponse
        if uploadedRideCount > 0 {
            response = try await request(
                path: ["v1", "rides"],
                accessToken: accessToken
            )
        } else {
            response = initialResponse
        }

        let failedRideIDs = Set(failures.map(\.rideID))
        var mergedRides = Dictionary(uniqueKeysWithValues: localRides.map { ($0.id, $0) })
        for cloudRide in response.rides where !failedRideIDs.contains(cloudRide.id) {
            mergedRides[cloudRide.id] = cloudRide
        }

        return RideCloudSyncResult(
            rides: mergedRides.values.sorted { $0.startedAt > $1.startedAt },
            uploadedRideCount: uploadedRideCount,
            failures: failures
        )
    }

    func delete(rideID: UUID, accessToken: String) async throws {
        let endpoint = ["v1", "rides", rideID.uuidString].reduce(baseURL) {
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
                statusCode: httpResponse.statusCode,
                message: serverError?.message ?? HTTPURLResponse.localizedString(
                    forStatusCode: httpResponse.statusCode
                ),
                requestID: serverError?.requestId
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
                statusCode: httpResponse.statusCode,
                message: serverError?.message ?? HTTPURLResponse.localizedString(
                    forStatusCode: httpResponse.statusCode
                ),
                requestID: serverError?.requestId
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

struct RideCloudSyncResult {
    let rides: [RideSession]
    let uploadedRideCount: Int
    let failures: [RideCloudUploadFailure]
}

struct RideCloudUploadFailure {
    let rideID: UUID
    let title: String
    let error: Error

    var userFacingReason: String {
        if let cloudError = error as? RideCloudError {
            return cloudError.userFacingReason
        }
        if let urlError = error as? URLError {
            return urlError.code == .notConnectedToInternet
                ? "网络未连接"
                : "网络连接失败"
        }
        return "服务器拒绝了该记录"
    }

    var diagnosticDescription: String {
        "\(title) [\(rideID.uuidString.lowercased())]: \(error.localizedDescription)"
    }

    var isIncompatibleRecord: Bool {
        guard let cloudError = error as? RideCloudError,
              case let .server(statusCode, _, _) = cloudError else {
            return false
        }
        return statusCode == 400
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
    let requestId: String?
}

enum RideCloudError: LocalizedError {
    case invalidResponse
    case server(statusCode: Int, message: String, requestID: String?)

    var userFacingReason: String {
        switch self {
        case .invalidResponse:
            return "服务器响应异常"
        case let .server(statusCode, _, _):
            switch statusCode {
            case 400:
                return "记录格式不兼容"
            case 401, 403:
                return "登录状态已失效"
            case 413:
                return "轨迹数据超过代理上传限制"
            case 429:
                return "同步请求过于频繁"
            case 500...599:
                return "服务器暂时不可用"
            default:
                return "服务器返回 HTTP \(statusCode)"
            }
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "服务器返回了无法识别的响应。"
        case let .server(statusCode, message, requestID):
            ["HTTP \(statusCode)", message, requestID.map { "requestId=\($0)" }]
                .compactMap { $0 }
                .joined(separator: " · ")
        }
    }
}
