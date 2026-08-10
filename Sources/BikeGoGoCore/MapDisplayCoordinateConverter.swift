import Foundation

public struct MapDisplayCoordinate: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum MapDisplayCoordinateConverter {
    private static let earthSemiMajorAxis = 6_378_245.0
    private static let eccentricitySquared = 0.006693421622965943

    public static func coordinate(
        latitude: Double,
        longitude: Double
    ) -> MapDisplayCoordinate {
        guard isInMainlandChina(latitude: latitude, longitude: longitude) else {
            return MapDisplayCoordinate(latitude: latitude, longitude: longitude)
        }

        let latitudeOffset = transformLatitude(
            longitude - 105,
            latitude - 35
        )
        let longitudeOffset = transformLongitude(
            longitude - 105,
            latitude - 35
        )
        let latitudeRadians = latitude / 180 * .pi
        let sine = sin(latitudeRadians)
        let magic = 1 - eccentricitySquared * sine * sine
        let squareRootMagic = sqrt(magic)
        let adjustedLatitude = latitudeOffset * 180
            / ((earthSemiMajorAxis * (1 - eccentricitySquared))
                / (magic * squareRootMagic) * .pi)
        let adjustedLongitude = longitudeOffset * 180
            / (earthSemiMajorAxis / squareRootMagic
                * cos(latitudeRadians) * .pi)

        return MapDisplayCoordinate(
            latitude: latitude + adjustedLatitude,
            longitude: longitude + adjustedLongitude
        )
    }

    public static func isInMainlandChina(
        latitude: Double,
        longitude: Double
    ) -> Bool {
        guard latitude >= 0.8293,
              latitude <= 55.8271,
              longitude >= 72.004,
              longitude <= 137.8347 else {
            return false
        }

        let isHongKong = (22.11...22.58).contains(latitude)
            && (113.82...114.52).contains(longitude)
        let isMacau = (22.08...22.23).contains(latitude)
            && (113.52...113.65).contains(longitude)
        let isTaiwan = (21.8...25.5).contains(latitude)
            && (119.9...122.1).contains(longitude)
        return !isHongKong && !isMacau && !isTaiwan
    }

    private static func transformLatitude(_ x: Double, _ y: Double) -> Double {
        var result = -100 + 2 * x + 3 * y + 0.2 * y * y
            + 0.1 * x * y + 0.2 * sqrt(abs(x))
        result += (20 * sin(6 * x * .pi) + 20 * sin(2 * x * .pi)) * 2 / 3
        result += (20 * sin(y * .pi) + 40 * sin(y / 3 * .pi)) * 2 / 3
        result += (160 * sin(y / 12 * .pi) + 320 * sin(y * .pi / 30)) * 2 / 3
        return result
    }

    private static func transformLongitude(_ x: Double, _ y: Double) -> Double {
        var result = 300 + x + 2 * y + 0.1 * x * x
            + 0.1 * x * y + 0.1 * sqrt(abs(x))
        result += (20 * sin(6 * x * .pi) + 20 * sin(2 * x * .pi)) * 2 / 3
        result += (20 * sin(x * .pi) + 40 * sin(x / 3 * .pi)) * 2 / 3
        result += (150 * sin(x / 12 * .pi) + 300 * sin(x / 30 * .pi)) * 2 / 3
        return result
    }
}
