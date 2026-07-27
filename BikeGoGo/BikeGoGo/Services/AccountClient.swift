import Combine
import Foundation

struct AppUser: Codable, Identifiable, Equatable {
    let id: String
    var displayName: String
    let friendCode: String
    let authProvider: String?
    let createdAt: String
    let updatedAt: String

    var isAppleAccount: Bool {
        authProvider == "apple"
    }
}

struct AppFriendRequest: Codable, Identifiable, Equatable {
    let id: String
    let status: String
    let createdAt: String
    let updatedAt: String
    let user: AppUser
}

struct AppGroup: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let owner: AppUser
    let members: [AppUser]
    let isOwner: Bool
    let createdAt: String
    let updatedAt: String
}

@MainActor
final class AccountClient: ObservableObject {
    @Published private(set) var currentUser: AppUser?
    @Published private(set) var friends: [AppUser] = []
    @Published private(set) var incomingRequests: [AppFriendRequest] = []
    @Published private(set) var outgoingRequests: [AppFriendRequest] = []
    @Published private(set) var groups: [AppGroup] = []
    @Published private(set) var accessToken: String?
    @Published private(set) var requiresAppleSignIn = false
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    var beforeSignOut: (() async -> Void)?

    private let baseURL: URL
    private let session: URLSession
    private let deviceID: String
    private static let deviceIDKey = "bikegogo.accountDeviceID"
    private static let accessTokenKey = "bikegogo.accountAccessToken"

    init(
        baseURL: URL? = nil,
        session: URLSession = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.baseURL = baseURL ?? AppConfiguration.apiBaseURL
        self.session = session

        if let storedID = KeychainStore.string(for: Self.deviceIDKey) {
            deviceID = storedID
        } else if let legacyID = defaults.string(forKey: Self.deviceIDKey) {
            deviceID = legacyID
            KeychainStore.set(legacyID, for: Self.deviceIDKey)
            defaults.removeObject(forKey: Self.deviceIDKey)
        } else {
            let newID = UUID().uuidString.lowercased()
            deviceID = newID
            KeychainStore.set(newID, for: Self.deviceIDKey)
        }
        accessToken = KeychainStore.string(for: Self.accessTokenKey)
    }

    func bootstrap(defaultDisplayName: String) async {
        guard !isWorking else { return }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }

        if accessToken != nil {
            do {
                try await loadSocialData()
                requiresAppleSignIn = false
                return
            } catch {
                guard isInvalidSession(error) else {
                    errorMessage = accountMessage(for: error)
                    return
                }
                clearSession()
            }
        }

        do {
            let body = try JSONEncoder().encode(
                GuestLoginBody(deviceId: deviceID, displayName: defaultDisplayName)
            )
            let response: GuestLoginResponse = try await request(
                path: ["v1", "auth", "guest"],
                method: "POST",
                body: body,
                authorization: .none
            )
            saveSession(response)
            try await loadSocialData()
        } catch {
            if isServerError(error, code: "apple_sign_in_required") {
                requiresAppleSignIn = true
            } else {
                errorMessage = accountMessage(for: error)
            }
        }
    }

    func signInWithApple(
        identityToken: String,
        rawNonce: String,
        displayName: String?
    ) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }

        do {
            let body = try JSONEncoder().encode(
                AppleLoginBody(
                    identityToken: identityToken,
                    rawNonce: rawNonce,
                    deviceId: deviceID,
                    displayName: displayName
                )
            )
            let response: GuestLoginResponse = try await request(
                path: ["v1", "auth", "apple"],
                method: "POST",
                body: body,
                authorization: .optional
            )
            saveSession(response)
            try await loadSocialData()
            requiresAppleSignIn = false
            statusMessage = "Apple 账户已连接"
            return true
        } catch {
            errorMessage = accountMessage(for: error)
            return false
        }
    }

    func signOut() async {
        guard !isWorking else { return }
        let wasAppleAccount = currentUser?.isAppleAccount == true
        isWorking = true
        defer { isWorking = false }

        await beforeSignOut?()
        if accessToken != nil {
            do {
                try await requestNoContent(
                    path: ["v1", "session"],
                    method: "DELETE"
                )
            } catch where !isInvalidSession(error) {
                errorMessage = accountMessage(for: error)
            } catch {}
        }

        clearSession()
        requiresAppleSignIn = wasAppleAccount
    }

    func refresh() async {
        guard accessToken != nil, !isWorking else { return }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }

        do {
            try await loadSocialData()
        } catch {
            if isInvalidSession(error) {
                let requiresSignIn = currentUser?.isAppleAccount == true
                clearSession()
                requiresAppleSignIn = requiresSignIn
            } else {
                errorMessage = accountMessage(for: error)
            }
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

    func createGroup(name: String) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }

        do {
            let body = try JSONEncoder().encode(GroupNameBody(name: name))
            let _: GroupResponse = try await request(
                path: ["v1", "groups"],
                method: "POST",
                body: body
            )
            try await loadGroups()
            statusMessage = "小队已创建"
            return true
        } catch {
            errorMessage = accountMessage(for: error)
            return false
        }
    }

    func addMember(groupID: String, userID: String) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            let body = try JSONEncoder().encode(GroupMemberBody(userId: userID))
            let _: GroupResponse = try await request(
                path: ["v1", "groups", groupID, "members"],
                method: "POST",
                body: body
            )
            try await loadGroups()
            statusMessage = "成员已加入小队"
        } catch {
            errorMessage = accountMessage(for: error)
        }
    }

    func removeMember(groupID: String, userID: String) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            let _: GroupResponse = try await request(
                path: ["v1", "groups", groupID, "members", userID],
                method: "DELETE"
            )
            try await loadGroups()
            statusMessage = "成员已移出小队"
        } catch {
            errorMessage = accountMessage(for: error)
        }
    }

    func leaveGroup(groupID: String) async {
        guard let userID = currentUser?.id else { return }
        await removeMember(groupID: groupID, userID: userID)
    }

    func deleteGroup(groupID: String) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            try await requestNoContent(
                path: ["v1", "groups", groupID],
                method: "DELETE"
            )
            try await loadGroups()
            statusMessage = "小队已解散"
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
        let groupList: GroupsResponse? = try? await request(path: ["v1", "groups"])
        currentUser = me.user
        friends = friendList.friends
        incomingRequests = requests.incoming
        outgoingRequests = requests.outgoing
        groups = groupList?.groups ?? []
    }

    private func loadGroups() async throws {
        let response: GroupsResponse = try await request(path: ["v1", "groups"])
        groups = response.groups
    }

    private func request<Response: Decodable>(
        path: [String],
        method: String = "GET",
        body: Data? = nil,
        authorization: Authorization = .required
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
        if authorization == .required {
            guard let accessToken else { throw AccountError.notAuthenticated }
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        } else if authorization == .optional, let accessToken {
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

    private func requestNoContent(path: [String], method: String) async throws {
        let endpoint = path.reduce(baseURL) { url, component in
            url.appending(path: component)
        }
        guard let accessToken else { throw AccountError.notAuthenticated }

        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
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
    }

    private func saveSession(_ response: GuestLoginResponse) {
        accessToken = response.accessToken
        currentUser = response.user
        KeychainStore.set(response.accessToken, for: Self.accessTokenKey)
    }

    private func clearSession() {
        accessToken = nil
        currentUser = nil
        friends = []
        incomingRequests = []
        outgoingRequests = []
        groups = []
        KeychainStore.delete(Self.accessTokenKey)
    }

    private func isInvalidSession(_ error: Error) -> Bool {
        guard case let AccountError.server(code, statusCode) = error else {
            return false
        }
        return statusCode == 401 || code == "invalid_session"
    }

    private func isServerError(_ error: Error, code expectedCode: String) -> Bool {
        guard case let AccountError.server(code, _) = error else { return false }
        return code == expectedCode
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
            case "invalid_session": return "账户会话已失效，请重新登录。"
            case "invalid_apple_identity": return "Apple 身份验证失败，请重新尝试。"
            case "apple_account_mismatch": return "当前账户已经连接了另一个 Apple ID。"
            case "apple_sign_in_required": return "请使用 Apple 登录以继续使用这个账户。"
            case "group_owner_required": return "只有小队创建者可以执行这个操作。"
            case "group_member_must_be_friend": return "只能邀请已经互相同意的好友。"
            case "group_member_limit": return "每个小队最多 20 人。"
            case "group_owner_cannot_leave": return "创建者需要解散小队，不能直接退出。"
            case "group_membership_required": return "你已经不在这个小队中。"
            default: return "操作没有完成，请稍后重试。"
            }
        }
    }
}

private enum Authorization {
    case none
    case optional
    case required
}

private struct GuestLoginBody: Encodable {
    let deviceId: String
    let displayName: String
}

private struct AppleLoginBody: Encodable {
    let identityToken: String
    let rawNonce: String
    let deviceId: String
    let displayName: String?
}

private struct ProfileBody: Encodable {
    let displayName: String
}

private struct FriendCodeBody: Encodable {
    let friendCode: String
}

private struct GroupNameBody: Encodable {
    let name: String
}

private struct GroupMemberBody: Encodable {
    let userId: String
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

private struct GroupsResponse: Decodable {
    let groups: [AppGroup]
}

private struct GroupResponse: Decodable {
    let group: AppGroup
}

private struct ServerErrorResponse: Decodable {
    let error: String
}

private enum AccountError: Error {
    case notAuthenticated
    case invalidResponse
    case server(code: String, statusCode: Int)
}
