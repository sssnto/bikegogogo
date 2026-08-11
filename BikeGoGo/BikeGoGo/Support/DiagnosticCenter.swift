import Foundation
import MetricKit
import UIKit

@MainActor
final class DiagnosticCenter: NSObject, MXMetricManagerSubscriber {
    static let shared = DiagnosticCenter()

    private struct NetworkFailure: Codable {
        let recordedAt: String
        let statusCode: Int
        let requestID: String?
    }

    private let networkFailureKey = "bikegogo.diagnostics.networkFailures"
    private let maximumNetworkFailures = 20
    private let maximumPayloadFiles = 6
    private var hasStarted = false

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        MXMetricManager.shared.add(self)
    }

    func recordNetworkFailure(statusCode: Int, requestID: String?) {
        var failures = storedNetworkFailures()
        failures.append(
            NetworkFailure(
                recordedAt: ISO8601DateFormatter().string(from: Date()),
                statusCode: statusCode,
                requestID: requestID
            )
        )
        failures = Array(failures.suffix(maximumNetworkFailures))
        if let data = try? JSONEncoder().encode(failures) {
            UserDefaults.standard.set(data, forKey: networkFailureKey)
        }
    }

    func exportReport() throws -> URL {
        let bundle = Bundle.main
        let device = UIDevice.current
        let payloads = try storedPayloads()
        let failures = storedNetworkFailures().map { failure in
            var item: [String: Any] = [
                "recordedAt": failure.recordedAt,
                "statusCode": failure.statusCode
            ]
            if let requestID = failure.requestID {
                item["requestId"] = requestID
            }
            return item
        }
        let report: [String: Any] = [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "privacy": [
                "createdByUserAction": true,
                "containsLocation": false,
                "containsHealthData": false,
                "containsAccountOrDeviceTokens": false
            ],
            "application": [
                "name": bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? "BikeGoGo",
                "version": bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                    ?? "unknown",
                "build": bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
                    ?? "unknown"
            ],
            "system": [
                "deviceModel": device.model,
                "systemName": device.systemName,
                "systemVersion": device.systemVersion
            ],
            "recentNetworkFailures": failures,
            "metricKitReports": payloads
        ]
        let data = try JSONSerialization.data(
            withJSONObject: report,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        let filename = "BikeGoGo-diagnostics-\(Int(Date().timeIntervalSince1970)).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: [.atomic])
        return url
    }

    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        let data = payloads.map { $0.jsonRepresentation() }
        Task { @MainActor in
            for payload in data {
                DiagnosticCenter.shared.store(payload, kind: "metrics")
            }
        }
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let data = payloads.map { $0.jsonRepresentation() }
        Task { @MainActor in
            for payload in data {
                DiagnosticCenter.shared.store(payload, kind: "diagnostics")
            }
        }
    }

    private func storedNetworkFailures() -> [NetworkFailure] {
        guard let data = UserDefaults.standard.data(forKey: networkFailureKey) else {
            return []
        }
        return (try? JSONDecoder().decode([NetworkFailure].self, from: data)) ?? []
    }

    private func store(_ payload: Data, kind: String) {
        do {
            let payloadObject = try JSONSerialization.jsonObject(with: payload)
            let storedReport: [String: Any] = [
                "kind": kind,
                "receivedAt": ISO8601DateFormatter().string(from: Date()),
                "payload": payloadObject
            ]
            let data = try JSONSerialization.data(
                withJSONObject: storedReport,
                options: [.sortedKeys, .withoutEscapingSlashes]
            )
            let directory = try diagnosticsDirectory()
            let filename = "\(kind)-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString).json"
            try data.write(
                to: directory.appendingPathComponent(filename),
                options: [.atomic]
            )
            try prunePayloadFiles(in: directory)
        } catch {
            // Diagnostics must never interrupt app launch or riding workflows.
        }
    }

    private func storedPayloads() throws -> [Any] {
        let directory = try diagnosticsDirectory()
        return try payloadFiles(in: directory).compactMap { url in
            let data = try Data(contentsOf: url)
            return try JSONSerialization.jsonObject(with: data)
        }
    }

    private func diagnosticsDirectory() throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        var directory = applicationSupport.appendingPathComponent(
            "BikeGoGoDiagnostics",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        return directory
    }

    private func payloadFiles(in directory: URL) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .sorted { lhs, rhs in
            let leftDate = try? lhs.resourceValues(forKeys: keys).contentModificationDate
            let rightDate = try? rhs.resourceValues(forKeys: keys).contentModificationDate
            return (leftDate ?? .distantPast) < (rightDate ?? .distantPast)
        }
    }

    private func prunePayloadFiles(in directory: URL) throws {
        let files = try payloadFiles(in: directory)
        for url in files.dropLast(maximumPayloadFiles) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
