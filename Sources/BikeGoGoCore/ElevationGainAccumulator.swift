import Foundation

public struct ElevationGainAccumulator: Sendable {
    public private(set) var elevationGainMeters = 0.0

    private var referenceAltitudeMeters: Double?
    private let minimumChangeMeters: Double
    private let maximumVerticalAccuracyMeters: Double

    public init(
        minimumChangeMeters: Double = 2.5,
        maximumVerticalAccuracyMeters: Double = 25
    ) {
        self.minimumChangeMeters = minimumChangeMeters
        self.maximumVerticalAccuracyMeters = maximumVerticalAccuracyMeters
    }

    public mutating func add(
        altitudeMeters: Double,
        verticalAccuracyMeters: Double?
    ) {
        guard altitudeMeters.isFinite else { return }
        if let verticalAccuracyMeters {
            guard verticalAccuracyMeters >= 0,
                  verticalAccuracyMeters <= maximumVerticalAccuracyMeters else { return }
        }

        guard let referenceAltitudeMeters else {
            self.referenceAltitudeMeters = altitudeMeters
            return
        }

        let accuracyThreshold = verticalAccuracyMeters.map { min($0 * 0.35, 6) } ?? 0
        let threshold = max(minimumChangeMeters, accuracyThreshold)
        let change = altitudeMeters - referenceAltitudeMeters
        guard abs(change) >= threshold else { return }

        if change > 0 {
            elevationGainMeters += change
        }
        self.referenceAltitudeMeters = altitudeMeters
    }
}
