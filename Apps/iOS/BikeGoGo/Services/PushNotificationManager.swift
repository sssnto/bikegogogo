import UIKit
import UserNotifications

private struct PushTokenBody: Encodable {
    let token: String
    let environment: String
}

enum VoicePushEvent: Equatable {
    case invitation
    case cancelled(invitationID: String)
}

struct TeamSOSPushEvent: Equatable {
    let groupID: String
    let groupName: String
    let senderUserID: String
    let senderName: String
    let latitude: Double
    let longitude: Double
    let capturedAt: String
}

@MainActor
final class PushNotificationManager {
    static let shared = PushNotificationManager()

    private let session: URLSession
    private let defaults: UserDefaults
    private var accessToken: String?
    private var deviceToken: String?
    private var pendingVoiceEvents: [VoicePushEvent] = []
    private var pendingTeamSOSEvents: [TeamSOSPushEvent] = []
    var onVoiceEvent: ((VoicePushEvent) -> Void)?
    var onTeamSOSEvent: ((TeamSOSPushEvent) -> Void)?
    private static let deviceTokenKey = "bikegogo.pushDeviceToken"

    private var environment: String {
        let configured = Bundle.main.object(
            forInfoDictionaryKey: "BikeGoGoPushEnvironment"
        ) as? String
        return configured == "production" ? "production" : "sandbox"
    }

    private init(
        session: URLSession = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.session = session
        self.defaults = defaults
        deviceToken = defaults.string(forKey: Self.deviceTokenKey)
    }

    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            print("Notification authorization failed: \(error.localizedDescription)")
        }
    }

    func presentTeamSafetyNotification(
        identifier: String,
        title: String,
        body: String
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "team_ride_safety"
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Team safety notification failed: \(error.localizedDescription)")
        }
    }

    func configure(accessToken newAccessToken: String?) async {
        if accessToken != newAccessToken,
           let oldAccessToken = accessToken,
           let deviceToken {
            try? await updateRegistration(
                method: "DELETE",
                token: deviceToken,
                accessToken: oldAccessToken
            )
        }

        accessToken = newAccessToken
        await registerCurrentToken()
    }

    func didRegister(deviceToken data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        deviceToken = token
        defaults.set(token, forKey: Self.deviceTokenKey)
        Task {
            await registerCurrentToken()
        }
    }

    func didFailToRegister(error: Error) {
        print("Remote notification registration failed: \(error.localizedDescription)")
    }

    func unregisterCurrentToken(accessToken: String) async {
        guard let deviceToken else { return }
        try? await updateRegistration(
            method: "DELETE",
            token: deviceToken,
            accessToken: accessToken
        )
        if self.accessToken == accessToken {
            self.accessToken = nil
        }
    }

    @discardableResult
    func handleNotification(userInfo: [AnyHashable: Any]) -> Bool {
        guard let event = userInfo["event"] as? String else { return false }
        if event == "group_sos" {
            guard let teamSOSEvent = Self.teamSOSEvent(from: userInfo) else {
                return false
            }
            if let onTeamSOSEvent {
                onTeamSOSEvent(teamSOSEvent)
            } else {
                pendingTeamSOSEvents.append(teamSOSEvent)
            }
            return true
        }

        let voiceEvent: VoicePushEvent
        switch event {
        case "voice_invitation":
            voiceEvent = .invitation
        case "voice_cancelled":
            guard let invitationID = (userInfo["invitationId"] ?? userInfo["entityId"])
                as? String else {
                return false
            }
            voiceEvent = .cancelled(invitationID: invitationID)
        default:
            return false
        }

        if let onVoiceEvent {
            onVoiceEvent(voiceEvent)
        } else {
            pendingVoiceEvents.append(voiceEvent)
        }
        return true
    }

    func deliverPendingVoiceEvents() {
        guard let onVoiceEvent else { return }
        let events = pendingVoiceEvents
        pendingVoiceEvents.removeAll()
        events.forEach(onVoiceEvent)
    }

    func deliverPendingTeamSOSEvents() {
        guard let onTeamSOSEvent else { return }
        let events = pendingTeamSOSEvents
        pendingTeamSOSEvents.removeAll()
        events.forEach(onTeamSOSEvent)
    }

    private static func teamSOSEvent(
        from userInfo: [AnyHashable: Any]
    ) -> TeamSOSPushEvent? {
        guard let groupID = (userInfo["groupId"] ?? userInfo["entityId"]) as? String,
              let groupName = userInfo["groupName"] as? String,
              let senderUserID = userInfo["senderUserId"] as? String,
              let senderName = userInfo["senderName"] as? String,
              let latitudeText = userInfo["latitude"] as? String,
              let latitude = Double(latitudeText),
              let longitudeText = userInfo["longitude"] as? String,
              let longitude = Double(longitudeText),
              let capturedAt = userInfo["capturedAt"] as? String else {
            return nil
        }
        return TeamSOSPushEvent(
            groupID: groupID,
            groupName: groupName,
            senderUserID: senderUserID,
            senderName: senderName,
            latitude: latitude,
            longitude: longitude,
            capturedAt: capturedAt
        )
    }

    private func registerCurrentToken() async {
        guard let accessToken, let deviceToken else { return }
        do {
            try await updateRegistration(
                method: "PUT",
                token: deviceToken,
                accessToken: accessToken
            )
        } catch {
            print("Push token synchronization failed: \(error.localizedDescription)")
        }
    }

    private func updateRegistration(
        method: String,
        token: String,
        accessToken: String
    ) async throws {
        let url = AppConfiguration.apiBaseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("devices")
            .appendingPathComponent("push-token")
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            PushTokenBody(token: token, environment: environment)
        )

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}

@MainActor
final class BikeGoGoAppDelegate: NSObject, UIApplicationDelegate,
    UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [
            UIApplication.LaunchOptionsKey: Any
        ]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        DiagnosticCenter.shared.start()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushNotificationManager.shared.didRegister(deviceToken: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        PushNotificationManager.shared.didFailToRegister(error: error)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if PushNotificationManager.shared.handleNotification(
            userInfo: notification.request.content.userInfo
        ) {
            return [.sound]
        }
        return [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        PushNotificationManager.shared.handleNotification(
            userInfo: response.notification.request.content.userInfo
        )
    }
}
