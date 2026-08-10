import Foundation

public enum RideStatisticsCalculator {
    private static let earthRadiusMeters = 6_371_000.0
    private static let minimumMovingSpeedMetersPerSecond = 0.8

    public static func metrics(for points: [RidePoint]) -> RideMetrics {
        guard points.count > 1 else {
            return RideMetrics()
        }

        let ordered = points.sorted { $0.timestamp < $1.timestamp }
        var distanceMeters = 0.0
        var movingDurationSeconds = 0.0
        var maxSpeedMetersPerSecond = 0.0
        var elevationGainMeters = 0.0
        var previousElevation = ordered.first?.elevationMeters

        for pair in zip(ordered, ordered.dropFirst()) {
            let segmentDistance = distance(from: pair.0, to: pair.1)
            let segmentDuration = pair.1.timestamp.timeIntervalSince(pair.0.timestamp)
            guard segmentDuration > 0 else {
                continue
            }

            distanceMeters += segmentDistance
            let calculatedSpeed = segmentDistance / segmentDuration
            let reportedSpeed = pair.1.speedMetersPerSecond ?? calculatedSpeed
            maxSpeedMetersPerSecond = max(maxSpeedMetersPerSecond, reportedSpeed)

            if reportedSpeed >= minimumMovingSpeedMetersPerSecond {
                movingDurationSeconds += segmentDuration
            }

            if let elevation = pair.1.elevationMeters {
                if let previousElevation, elevation > previousElevation {
                    elevationGainMeters += elevation - previousElevation
                }
                previousElevation = elevation
            }
        }

        let heartRates = ordered.compactMap(\.heartRateBeatsPerMinute)
        let cadences = ordered.compactMap(\.cadenceRPM).map(Double.init)
        let powers = ordered.compactMap(\.cyclingPowerWatts)
        let elapsedDurationSeconds = ordered.last!.timestamp.timeIntervalSince(ordered.first!.timestamp)
        let averageSpeed = movingDurationSeconds > 0 ? distanceMeters / movingDurationSeconds : 0

        return RideMetrics(
            distanceMeters: distanceMeters,
            movingDurationSeconds: movingDurationSeconds,
            elapsedDurationSeconds: elapsedDurationSeconds,
            averageSpeedMetersPerSecond: averageSpeed,
            maxSpeedMetersPerSecond: maxSpeedMetersPerSecond,
            elevationGainMeters: elevationGainMeters,
            averageHeartRate: average(of: heartRates),
            maxHeartRate: heartRates.max(),
            averageCadenceRPM: average(of: cadences),
            maxCadenceRPM: cadences.max(),
            averageCyclingPowerWatts: average(of: powers),
            maxCyclingPowerWatts: powers.max()
        )
    }

    public static func distance(from start: RidePoint, to end: RidePoint) -> Double {
        let startLatitude = start.latitude * .pi / 180
        let endLatitude = end.latitude * .pi / 180
        let latitudeDelta = (end.latitude - start.latitude) * .pi / 180
        let longitudeDelta = (end.longitude - start.longitude) * .pi / 180

        let a = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(startLatitude) * cos(endLatitude)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusMeters * c
    }

    private static func average(of values: [Int]) -> Int? {
        guard !values.isEmpty else {
            return nil
        }

        return values.reduce(0, +) / values.count
    }

    private static func average(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
