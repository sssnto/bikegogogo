import Foundation

public enum GPXExporter {
    public static func document(for ride: RideSession) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let trackPoints = ride.points
            .sorted { $0.timestamp < $1.timestamp }
            .map { point in
                trackPointXML(for: point, formatter: formatter)
            }
            .joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="BikeGoGo" xmlns="http://www.topografix.com/GPX/1/1" xmlns:gpxdata="http://www.cluetrust.com/XML/GPXDATA/1/0">
          <metadata>
            <name>\(escape(ride.title))</name>
            <time>\(formatter.string(from: ride.startedAt))</time>
          </metadata>
          <trk>
            <name>\(escape(ride.title))</name>
            <type>cycling</type>
            <trkseg>
        \(trackPoints.indented(by: 6))
            </trkseg>
          </trk>
        </gpx>
        """
    }

    public static func suggestedFilename(for ride: RideSession) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: ride.startedAt)
        let sanitizedTitle = sanitizedFilenameComponent(from: ride.title)

        let titlePart = sanitizedTitle.isEmpty ? "ride" : sanitizedTitle
        return "\(timestamp)-\(titlePart).gpx"
    }

    private static func trackPointXML(for point: RidePoint, formatter: ISO8601DateFormatter) -> String {
        var lines = [
            "<trkpt lat=\"\(point.latitude)\" lon=\"\(point.longitude)\">"
        ]

        if let elevation = point.elevationMeters {
            lines.append("  <ele>\(elevation)</ele>")
        }

        lines.append("  <time>\(formatter.string(from: point.timestamp))</time>")

        var extensions: [String] = []
        if let speed = point.speedMetersPerSecond {
            extensions.append("<gpxdata:speed>\(speed)</gpxdata:speed>")
        }
        if let heartRate = point.heartRateBeatsPerMinute {
            extensions.append("<gpxdata:hr>\(heartRate)</gpxdata:hr>")
        }
        if let cadence = point.cadenceRPM {
            extensions.append("<gpxdata:cadence>\(cadence)</gpxdata:cadence>")
        }

        if !extensions.isEmpty {
            lines.append("  <extensions>")
            lines.append(contentsOf: extensions.map { "    \($0)" })
            lines.append("  </extensions>")
        }

        lines.append("</trkpt>")
        return lines.joined(separator: "\n")
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func sanitizedFilenameComponent(from value: String) -> String {
        var result = ""
        var previousWasSeparator = false

        for character in value.lowercased() {
            let isAllowed = character.unicodeScalars.allSatisfy {
                $0.properties.isAlphabetic || $0.properties.numericType != nil
            }

            if isAllowed {
                result.append(character)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                result.append("-")
                previousWasSeparator = true
            }
        }

        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

private extension String {
    func indented(by spaces: Int) -> String {
        let padding = String(repeating: " ", count: spaces)
        return split(separator: "\n", omittingEmptySubsequences: false)
            .map { padding + String($0) }
            .joined(separator: "\n")
    }
}
