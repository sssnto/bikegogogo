import Combine
import Foundation

struct AppUser: Codable, Identifiable, Equatable {
    let id: String
    var displayName: String
    let friendCode: String
    let createdAt: String
    let updatedAt: String
}

struct AppFriendRequest: Codable, Identifiable, Equatable {
    let id: String
    let status: String
    let createdAt: String
    let updatedAt: String
    let user: AppUser
}

@MainActor
final class AccountClient: ObservableObject {
    @Published private(set) var currentUser: AppUser?
    @Published private(set) var friends: [AppUser] = []
    @Published private(set) var incomingRequests: [AppFriendRequest] = []
    @Published private(set) var outgoingRequests: [AppFriendRequest] = []
    @Published private(set) var accessToken: String?
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    private let baseURL: URL
    private let session: URLSession
    private let deviceID: String

    init(
        baseURL: URL? = nil,
        session: URLSession = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.baseURL = baseURL ?? AppConfiguration.apiBaseURL
        self.session = session

        let key = "bikegogo.accountDeviceID"
        if let storedID = defaults.string(forKey: key) {
            deviceID = storedID
        } else {
            let newID = UUID().uuidString.lowercased()
            defaults.set(newID, forKey: key)
            deviceID = newID
        }
    }

    func bootstrap(defaultDisplayName: String) async {
        guard accessToken == nil, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            let body = try JSONEncoder().encode(
                GuestLoginBody(deviceId: deviceID, displayName: defaultDisplayName)
            )
            let response: GuestLoginResponse = try await request(
                path: ["v1", "auth", "guest"],
                method: "POST",
                body: body,
                authorized: false
            )
            accessToken = response.accessToken
            currentUser = response.user
            try await loadSocialData()
        } catch {
            errorMessage = accountMessage(for: error)
        }
    }

    func refresh() async {
        guard accessToken != nil, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            try await loadSocialData()
        } catch {
            errorMessage = accountMessage(for: error)
        }
    }

    func updateDisplayName(_ displayName: String) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }

        do {
            let body = try JSONEncoder().encode(ProfileBody(displayName: displayName))
            let response: UserResponse = try await request(
                path: ["v1", "me"],
                method: "PATCH",
                body: body
            )
            currentUser = response.user
            statusMessage = "昵称已更新"
            return true
        } catch {
            errorMessage = accountMessage(for: error)
            return false
        }
    }

    func sendFriendRequest(friendCode: String) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }

        do {
            let body = try JSONEncoder().encode(
                FriendCodeBody(friendCode: friendCode.uppercased())
            )
            let response: FriendRequestResponse = try await request(
                path: ["v1", "friends", "requests"],
                method: "POST",
                body: body
            )
            try await loadSocialData()
            statusMessage = response.request.status == "accepted"
                ? "你们已互相添加为好友"
                : "好友申请已发送"
            return true
        } catch {
            errorMessage = accountMessage(for: error)
            return false
        }
    }

    func respond(to requestID: String, accept: Bool) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            let action = accept ? "accept" : "reject"
            let _: FriendRequestActionResponse = try await request(
                path: ["v1", "friends", "requests", requestID, action],
                method: "POST"
            )
            try await loadSocialData()
            statusMessage = accept ? "已添加好友" : "已拒绝好友申请"
        } catch {
            errorMessage = accountMessage(for: error)
        }
    }

    func dismissMessages() {
        errorMessage = nil
        statusMessage = nil
    }

    private func loadSocialData() async throws {
        let me: UserResponse = try await request(path: ["v1", "me"])
        let friendList: FriendsResponse = try await request(path: ["v1", "friends"])
        let requests: FriendRequestsResponse = try await request(
            path: ["v1", "friends", "requests"]
        )
        currentUser = me.user
        friends = friendList.friends
        incomingRequests = requests.incoming
        outgoingRequests = requests.outgoing
    }

    private func request<Response: Decodable>(
        path: [String],
        method: String = "GET",
        body: Data? = nil,
        authorized: Bool = true
    ) async throws -> Response {
        let endpoint = path.reduce(baseURL) { url, component in
            url.appending(path: component)
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authorized {
            guard let accessToken else { throw AccountError.notAuthenticated }
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AccountError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let serverError = try? JSONDecoder().decode(ServerErrorResponse.self, from: data)
            throw AccountError.server(
                code: serverError?.error ?? "request_failed",
                statusCode: httpResponse.statusCode
            )
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func accountMessage(for error: Error) -> String {
        guard let accountError = error as? AccountError else {
            return "无法连接服务器，请检查网络和后端地址。"
        }

        switch accountError {
        case .notAuthenticated:
            return "账户会话尚未建立，请稍后重试。"
        case .invalidResponse:
            return "服务器返回了无法识别的响应。"
        case let .server(code, _):
            switch code {
            case "friend_code_not_found": return "没有找到这个好友码。"
            case "cannot_add_self": return "不能添加自己为好友。"
            case "already_friends": return "你们已经是好友了。"
            case "request_already_resolved": return "这条好友申请已经处理过了。"
            case "invalid_session": return "账户会话已失效，请重新启动应用。"
            default: return "操作没有完成，请稍后重试。"
            }
        }
    }
}

private struct GuestLoginBody: Encodable {
    let deviceId: String
    let displayName: String
}

private struct ProfileBody: Encodable {
    let displayName: String
}

private struct FriendCodeBody: Encodable {
    let friendCode: String
}

private struct GuestLoginResponse: Decodable {
    let accessToken: String
    let user: AppUser
}

private struct UserResponse: Decodable {
    let user: AppUser
}

private struct FriendsResponse: Decodable {
    let friends: [AppUser]
}

private struct FriendRequestsResponse: Decodable {
    let incoming: [AppFriendRequest]
    let outgoing: [AppFriendRequest]
}

private struct FriendRequestResponse: Decodable {
    let request: AppFriendRequest
}

private struct FriendRequestActionResponse: Decodable {
    struct Request: Decodable {
        let id: String
        let status: String
    }

    let request: Request
}

private struct ServerErrorResponse: Decodable {
    let error: String
}

private enum AccountError: Error {
    case notAuthenticated
    case invalidResponse
    case server(code: String, statusCode: Int)
}
