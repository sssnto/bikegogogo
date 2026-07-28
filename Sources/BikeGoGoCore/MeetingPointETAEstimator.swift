import Foundation

public enum MeetingPointETASource: Equatable, Sendable {
    case currentSpeed
    case averageSpeed
}

public struct MeetingPointETAEvaluation: Equatable, Sendable {
    public let durationSeconds: TimeInterval
    public let speedMetersPerSecond: Double
    public let source: MeetingPointETASource

    public init(
        durationSeconds: TimeInterval,
        speedMetersPerSecond: Double,
        source: MeetingPointETASource
    ) {
        self.durationSeconds = durationSeconds
        self.speedMetersPerSecond = speedMetersPerSecond
        self.source = source
    }
}

public enum MeetingPointETAEstimator {
    public static func estimate(
        distanceMeters: Double,
        currentSpeedMetersPerSecond: Double?,
        averageSpeedMetersPerSecond: Double? = nil
    ) -> MeetingPointETAEvaluation? {
        guard distanceMeters.isFinite, distanceMeters >= 0 else {
            return nil
        }
        if distanceMeters <= 100 {
            return MeetingPointETAEvaluation(
                durationSeconds: 0,
                speedMetersPerSecond: 0,
                source: .currentSpeed
            )
        }

        let minimumUsefulSpeed = 1.5
        let maximumCyclingSpeed = 30.0
        let speedAndSource: (Double, MeetingPointETASource)?
        if let currentSpeedMetersPerSecond,
           currentSpeedMetersPerSecond >= minimumUsefulSpeed,
           currentSpeedMetersPerSecond <= maximumCyclingSpeed {
            speedAndSource = (currentSpeedMetersPerSecond, .currentSpeed)
        } else if let averageSpeedMetersPerSecond,
                  averageSpeedMetersPerSecond >= minimumUsefulSpeed,
                  averageSpeedMetersPerSecond <= maximumCyclingSpeed {
            speedAndSource = (averageSpeedMetersPerSecond, .averageSpeed)
        } else {
            speedAndSource = nil
        }

        guard let (speed, source) = speedAndSource else { return nil }
        let duration = distanceMeters / speed
        guard duration <= 6 * 60 * 60 else { return nil }
        return MeetingPointETAEvaluation(
            durationSeconds: duration,
            speedMetersPerSecond: speed,
            source: source
        )
    }
}
