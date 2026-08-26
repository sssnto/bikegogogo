import Foundation
import UIKit

actor TelemetryClient {
    static let shared = TelemetryClient()

    private struct Event: Codable, Identifiable {
        let id: UUID
        let eventName: String
        let occurredAt: Date
        let sessionId: UUID
        let appVersion: String
        let buildNumber: String
        let platform: String
        let osVersion: String
        let deviceFamily: String
        let properties: [String: String]

        enum CodingKeys: String, CodingKey {
            case id = "eventId"
            case eventName
            case occurredAt
            case sessionId
            case appVersion
            case buildNumber
            case platform
            case osVersion
            case deviceFamily
            case properties
        }
    }

    private struct Batch: Encodable {
        let events: [Event]
    }

    private static let pendingEventsKey = "bikegogo.pendingTelemetryEvents"
    private static let maximumPendingEvents = 200
    private static let maximumBatchSize = 50

    private var baseURL: URL
    private let session: URLSession
    private let defaults: UserDefaults
    private let sessionID = UUID()
    private var accessToken: String?
    private var pendingEvents: [Event]
    private var isFlushing = false

    init(
        baseURL: URL? = nil,
        session: URLSession = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.baseURL = baseURL ?? URL(string: "http://localhost:8080")!
        self.session = session
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.pendingEventsKey),
           let events = try? Self.decoder.decode([Event].self, from: data) {
            pendingEvents = Array(events.suffix(Self.maximumPendingEvents))
        } else {
            pendingEvents = []
        }
    }

    func configure(accessToken: String?, baseURL: URL? = nil) async {
        self.accessToken = accessToken
        if let baseURL {
            self.baseURL = baseURL
        }
        await flush()
    }

    func track(
        _ eventName: String,
        properties: [String: String] = [:]
    ) async {
        guard eventName.range(
            of: #"^[a-z][a-z0-9_.]{2,80}$"#,
            options: .regularExpression
        ) != nil else { return }

        let deviceMetadata = await MainActor.run {
            (
                osVersion: UIDevice.current.systemVersion,
                deviceFamily: UIDevice.current.userInterfaceIdiom == .pad
                    ? "iPad"
                    : "iPhone"
            )
        }
        let info = Bundle.main.infoDictionary
        pendingEvents.append(Event(
            id: UUID(),
            eventName: eventName,
            occurredAt: Date(),
            sessionId: sessionID,
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "unknown",
            buildNumber: info?["CFBundleVersion"] as? String ?? "unknown",
            platform: "iOS",
            osVersion: deviceMetadata.osVersion,
            deviceFamily: deviceMetadata.deviceFamily,
            properties: properties.mapValues { String($0.prefix(200)) }
        ))
        if pendingEvents.count > Self.maximumPendingEvents {
            pendingEvents.removeFirst(pendingEvents.count - Self.maximumPendingEvents)
        }
        persistPendingEvents()
        await flush()
    }

    private func flush() async {
        guard !isFlushing,
              let accessToken,
              !pendingEvents.isEmpty else { return }
        isFlushing = true
        defer { isFlushing = false }

        while !pendingEvents.isEmpty {
            let batch = Array(pendingEvents.prefix(Self.maximumBatchSize))
            do {
                var request = URLRequest(
                    url: baseURL
                        .appendingPathComponent("v1")
                        .appendingPathComponent("telemetry")
                        .appendingPathComponent("events")
                )
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                request.httpBody = try Self.encoder.encode(Batch(events: batch))

                let (_, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 202 else { return }

                let acceptedIDs = Set(batch.map(\.id))
                pendingEvents.removeAll { acceptedIDs.contains($0.id) }
                persistPendingEvents()
            } catch {
                return
            }
        }
    }

    private func persistPendingEvents() {
        guard let data = try? Self.encoder.encode(pendingEvents) else { return }
        defaults.set(data, forKey: Self.pendingEventsKey)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
