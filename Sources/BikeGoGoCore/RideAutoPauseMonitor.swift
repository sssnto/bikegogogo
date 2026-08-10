import Foundation

public enum RideAutoPauseAction: Equatable, Sendable {
    case none
    case pause
    case resume
}

public struct RideAutoPauseMonitor: Sendable {
    public struct Configuration: Sendable {
        public var pauseSpeedMetersPerSecond: Double
        public var resumeSpeedMetersPerSecond: Double
        public var pauseDelaySeconds: TimeInterval
        public var resumeDelaySeconds: TimeInterval
        public var maximumHorizontalAccuracyMeters: Double
        public var maximumSpeedAccuracyMetersPerSecond: Double

        public init(
            pauseSpeedMetersPerSecond: Double = 0.8,
            resumeSpeedMetersPerSecond: Double = 1.7,
            pauseDelaySeconds: TimeInterval = 20,
            resumeDelaySeconds: TimeInterval = 5,
            maximumHorizontalAccuracyMeters: Double = 25,
            maximumSpeedAccuracyMetersPerSecond: Double = 2
        ) {
            self.pauseSpeedMetersPerSecond = pauseSpeedMetersPerSecond
            self.resumeSpeedMetersPerSecond = resumeSpeedMetersPerSecond
            self.pauseDelaySeconds = pauseDelaySeconds
            self.resumeDelaySeconds = resumeDelaySeconds
            self.maximumHorizontalAccuracyMeters = maximumHorizontalAccuracyMeters
            self.maximumSpeedAccuracyMetersPerSecond = maximumSpeedAccuracyMetersPerSecond
        }
    }

    public let configuration: Configuration
    public private(set) var pauseDeadline: Date?

    private var stoppedSince: Date?
    private var movingSince: Date?

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public mutating func observe(
        speedMetersPerSecond: Double,
        horizontalAccuracyMeters: Double,
        speedAccuracyMetersPerSecond: Double?,
        at date: Date,
        isAutomaticallyPaused: Bool
    ) -> RideAutoPauseAction {
        guard horizontalAccuracyMeters >= 0,
              horizontalAccuracyMeters <= configuration.maximumHorizontalAccuracyMeters,
              speedAccuracyMetersPerSecond == nil
                || speedAccuracyMetersPerSecond! < 0
                || speedAccuracyMetersPerSecond!
                    <= configuration.maximumSpeedAccuracyMetersPerSecond else {
            stoppedSince = nil
            movingSince = nil
            pauseDeadline = nil
            return .none
        }

        if isAutomaticallyPaused {
            stoppedSince = nil
            pauseDeadline = nil
            if speedMetersPerSecond >= configuration.resumeSpeedMetersPerSecond {
                movingSince = movingSince ?? date
                if date.timeIntervalSince(movingSince!) >= configuration.resumeDelaySeconds {
                    movingSince = nil
                    return .resume
                }
            } else {
                movingSince = nil
            }
            return .none
        }

        movingSince = nil
        if speedMetersPerSecond <= configuration.pauseSpeedMetersPerSecond {
            stoppedSince = stoppedSince ?? date
            pauseDeadline = stoppedSince?.addingTimeInterval(
                configuration.pauseDelaySeconds
            )
            return evaluate(at: date, isAutomaticallyPaused: false)
        }

        stoppedSince = nil
        pauseDeadline = nil
        return .none
    }

    public mutating func evaluate(
        at date: Date,
        isAutomaticallyPaused: Bool
    ) -> RideAutoPauseAction {
        guard !isAutomaticallyPaused,
              let pauseDeadline,
              date >= pauseDeadline else {
            return .none
        }
        stoppedSince = nil
        self.pauseDeadline = nil
        return .pause
    }

    public mutating func reset() {
        stoppedSince = nil
        movingSince = nil
        pauseDeadline = nil
    }
}
