import UIKit
import UserNotifications

private struct PushTokenBody: Encodable {
    let token: String
    let environment: String
}

@MainActor
final class PushNotificationManager {
    static let shared = PushNotificationManager()

    private let session: URLSession
    private let defaults: UserDefaults
    private var accessToken: String?
    private var deviceToken: String?
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
        [.banner, .list, .sound]
    }
}
