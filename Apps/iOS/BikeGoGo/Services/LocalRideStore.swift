import BikeGoGoCore
import Foundation

actor LocalRideStore {
    private let fileManager: FileManager
    private let ridesURL: URL
    private let exportsDirectoryURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let appDirectory = applicationSupport.appendingPathComponent("BikeGoGo", isDirectory: true)

        self.ridesURL = appDirectory.appendingPathComponent("rides.json")
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
    static var bikeGoGo: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var bikeGoGo: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

