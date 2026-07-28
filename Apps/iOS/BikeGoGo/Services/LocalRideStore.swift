import BikeGoGoCore
import Foundation

actor LocalRideStore {
    private let fileManager: FileManager
    private let ridesURL: URL
    private let activeRideURL: URL
    private let exportsDirectoryURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let appDirectory = applicationSupport.appendingPathComponent("BikeGoGo", isDirectory: true)

        self.ridesURL = appDirectory.appendingPathComponent("rides.json")
        self.activeRideURL = appDirectory.appendingPathComponent("active-ride.json")
        self.exportsDirectoryURL = documents.appendingPathComponent("BikeGoGo Exports", isDirectory: true)
    }

    func loadRides() async throws -> [RideSession] {
        guard fileManager.fileExists(atPath: ridesURL.path) else {
            return []
        }

        let data = try Data(contentsOf: ridesURL)
        return try JSONDecoder.bikeGoGo.decode([RideSession].self, from: data)
    }

    func saveRides(_ rides: [RideSession]) async throws {
        try fileManager.createDirectory(
            at: ridesURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.bikeGoGo.encode(rides)
        try data.write(to: ridesURL, options: [.atomic])
    }

    func loadActiveRide() async throws -> RideSession? {
        guard fileManager.fileExists(atPath: activeRideURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: activeRideURL)
        return try JSONDecoder.bikeGoGo.decode(RideSession.self, from: data)
    }

    func saveActiveRide(_ ride: RideSession) async throws {
        try fileManager.createDirectory(
            at: activeRideURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.bikeGoGo.encode(ride)
        try data.write(to: activeRideURL, options: [.atomic])
    }

    func clearActiveRide() async throws {
        guard fileManager.fileExists(atPath: activeRideURL.path) else { return }
        try fileManager.removeItem(at: activeRideURL)
    }

    func deleteAllData() async throws {
        for url in [ridesURL, activeRideURL] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        if fileManager.fileExists(atPath: exportsDirectoryURL.path) {
            try fileManager.removeItem(at: exportsDirectoryURL)
        }
    }

    func exportGPX(for ride: RideSession) async throws -> URL {
        try fileManager.createDirectory(
            at: exportsDirectoryURL,
            withIntermediateDirectories: true
        )

        let url = exportsDirectoryURL.appendingPathComponent(GPXExporter.suggestedFilename(for: ride))
        let document = GPXExporter.document(for: ride)
        try document.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

private extension JSONEncoder {
    nonisolated static var bikeGoGo: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    nonisolated static var bikeGoGo: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
