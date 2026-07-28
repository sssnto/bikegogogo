import Foundation

public struct RideLocationFilter: Sendable {
    public static let maximumInitialHorizontalAccuracyMeters = 20.0
    public static let maximumTrackingHorizontalAccuracyMeters = 30.0

    private static let minimumDisplacementMeters = 5.0
    private static let maximumUncertaintyDisplacementMeters = 20.0
    private static let maximumCyclingSpeedMetersPerSecond = 30.0

    private var lastAcceptedPoint: RidePoint?

    public init(lastAcceptedPoint: RidePoint? = nil) {
        self.lastAcceptedPoint = lastAcceptedPoint
    }

    public mutating func reset(lastAcceptedPoint: RidePoint? = nil) {
        self.lastAcceptedPoint = lastAcceptedPoint
    }

    public mutating func accepts(_ candidate: RidePoint) -> Bool {
        guard candidate.latitude.isFinite,
              candidate.longitude.isFinite,
              (-90...90).contains(candidate.latitude),
              (-180...180).contains(candidate.longitude),
              let accuracy = candidate.horizontalAccuracyMeters,
              accuracy >= 0 else {
            return false
        }

        guard let previous = lastAcceptedPoint else {
            guard accuracy <= Self.maximumInitialHorizontalAccuracyMeters else {
                return false
            }
            lastAcceptedPoint = candidate
            return true
        }

        guard accuracy <= Self.maximumTrackingHorizontalAccuracyMeters else {
            return false
        }

        let duration = candidate.timestamp.timeIntervalSince(previous.timestamp)
        guard duration > 0 else {
            return false
        }

        let distance = RideStatisticsCalculator.distance(from: previous, to: candidate)
        let previousAccuracy = previous.horizontalAccuracyMeters ?? accuracy
        let uncertaintyThreshold = min(
            max(previousAccuracy, accuracy) * 0.75,
            Self.maximumUncertaintyDisplacementMeters
        )
        let minimumDisplacement = max(
            Self.minimumDisplacementMeters,
            uncertaintyThreshold
        )
        guard distance >= minimumDisplacement else {
            return false
        }

        let calculatedSpeed = distance / duration
        guard calculatedSpeed <= Self.maximumCyclingSpeedMetersPerSecond else {
            return false
        }

        if let reportedSpeed = candidate.speedMetersPerSecond {
            guard reportedSpeed <= Self.maximumCyclingSpeedMetersPerSecond else {
                return false
            }

            let allowedDifference = max(4, reportedSpeed * 2)
            if calculatedSpeed > 5,
               abs(calculatedSpeed - reportedSpeed) > allowedDifference {
                return false
            }
        }

        lastAcceptedPoint = candidate
        return true
    }
}
