import Foundation

public enum RideState: String, Codable, Sendable {
    case idle
    case recording
    case paused
    case finished
}

public enum RideSource: String, Codable, Sendable {
    case iPhone
    case appleWatch
    case merged
}

public struct RidePoint: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var elevationMeters: Double?
    public var speedMetersPerSecond: Double?
    public var courseDegrees: Double?
    public var horizontalAccuracyMeters: Double?
    public var heartRateBeatsPerMinute: Int?
    public var cadenceRPM: Int?
    public var cyclingPowerWatts: Double?
    public var timestamp: Date

    public init(
        latitude: Double,
        longitude: Double,
        elevationMeters: Double? = nil,
        speedMetersPerSecond: Double? = nil,
        courseDegrees: Double? = nil,
        horizontalAccuracyMeters: Double? = nil,
        heartRateBeatsPerMinute: Int? = nil,
        cadenceRPM: Int? = nil,
        cyclingPowerWatts: Double? = nil,
        timestamp: Date
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.elevationMeters = elevationMeters
        self.speedMetersPerSecond = speedMetersPerSecond
        self.courseDegrees = courseDegrees
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.heartRateBeatsPerMinute = heartRateBeatsPerMinute
        self.cadenceRPM = cadenceRPM
        self.cyclingPowerWatts = cyclingPowerWatts
        self.timestamp = timestamp
    }
}

public struct RideMetrics: Codable, Equatable, Sendable {
    public var distanceMeters: Double
    public var movingDurationSeconds: TimeInterval
    public var elapsedDurationSeconds: TimeInterval
    public var averageSpeedMetersPerSecond: Double
    public var maxSpeedMetersPerSecond: Double
    public var elevationGainMeters: Double
    public var averageHeartRate: Int?
    public var maxHeartRate: Int?
    public var activeEnergyKilocalories: Double?
    public var totalEnergyKilocalories: Double?
    public var averageCadenceRPM: Double?
    public var maxCadenceRPM: Double?
    public var averageCyclingPowerWatts: Double?
    public var maxCyclingPowerWatts: Double?

    public init(
        distanceMeters: Double = 0,
        movingDurationSeconds: TimeInterval = 0,
        elapsedDurationSeconds: TimeInterval = 0,
        averageSpeedMetersPerSecond: Double = 0,
        maxSpeedMetersPerSecond: Double = 0,
        elevationGainMeters: Double = 0,
        averageHeartRate: Int? = nil,
        maxHeartRate: Int? = nil,
        activeEnergyKilocalories: Double? = nil,
        totalEnergyKilocalories: Double? = nil,
        averageCadenceRPM: Double? = nil,
        maxCadenceRPM: Double? = nil,
        averageCyclingPowerWatts: Double? = nil,
        maxCyclingPowerWatts: Double? = nil
    ) {
        self.distanceMeters = distanceMeters
        self.movingDurationSeconds = movingDurationSeconds
        self.elapsedDurationSeconds = elapsedDurationSeconds
        self.averageSpeedMetersPerSecond = averageSpeedMetersPerSecond
        self.maxSpeedMetersPerSecond = maxSpeedMetersPerSecond
        self.elevationGainMeters = elevationGainMeters
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.totalEnergyKilocalories = totalEnergyKilocalories
        self.averageCadenceRPM = averageCadenceRPM
        self.maxCadenceRPM = maxCadenceRPM
        self.averageCyclingPowerWatts = averageCyclingPowerWatts
        self.maxCyclingPowerWatts = maxCyclingPowerWatts
    }
}

public struct RideSession: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var state: RideState
    public var source: RideSource
    public var startedAt: Date
    public var endedAt: Date?
    public var points: [RidePoint]
    public var metrics: RideMetrics

    public init(
        id: UUID = UUID(),
        title: String,
        state: RideState = .idle,
        source: RideSource = .iPhone,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        points: [RidePoint] = [],
        metrics: RideMetrics = RideMetrics()
    ) {
        self.id = id
        self.title = title
        self.state = state
        self.source = source
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.points = points
        self.metrics = metrics
    }
}

public extension RideMetrics {
    var distanceKilometers: Double {
        distanceMeters / 1_000
    }

    var averageSpeedKilometersPerHour: Double {
        averageSpeedMetersPerSecond * 3.6
    }

    var maxSpeedKilometersPerHour: Double {
        maxSpeedMetersPerSecond * 3.6
    }
}
