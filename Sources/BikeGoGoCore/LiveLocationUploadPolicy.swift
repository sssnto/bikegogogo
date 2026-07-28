import Foundation

public struct LiveLocationUploadPolicy: Sendable {
    public let minimumMovingIntervalSeconds: TimeInterval
    public let maximumMovingIntervalSeconds: TimeInterval
    public let minimumMovingDistanceMeters: Double
    public let minimumStationaryIntervalSeconds: TimeInterval
    public let stationaryHeartbeatIntervalSeconds: TimeInterval
    public let minimumStationaryDistanceMeters: Double

    private var lastUploadedPoint: RidePoint?
    private var lastUploadedAt: Date?

    public init(
        minimumMovingIntervalSeconds: TimeInterval = 8,
        maximumMovingIntervalSeconds: TimeInterval = 18,
        minimumMovingDistanceMeters: Double = 20,
        minimumStationaryIntervalSeconds: TimeInterval = 25,
        stationaryHeartbeatIntervalSeconds: TimeInterval = 45,
        minimumStationaryDistanceMeters: Double = 15
    ) {
        self.minimumMovingIntervalSeconds = minimumMovingIntervalSeconds
        self.maximumMovingIntervalSeconds = maximumMovingIntervalSeconds
        self.minimumMovingDistanceMeters = minimumMovingDistanceMeters
        self.minimumStationaryIntervalSeconds = minimumStationaryIntervalSeconds
        self.stationaryHeartbeatIntervalSeconds = stationaryHeartbeatIntervalSeconds
        self.minimumStationaryDistanceMeters = minimumStationaryDistanceMeters
    }

    public func shouldUpload(
        _ candidate: RidePoint,
        at now: Date = Date(),
        force: Bool = false
    ) -> Bool {
        if force || lastUploadedPoint == nil || lastUploadedAt == nil {
            return true
        }
        guard let lastUploadedPoint, let lastUploadedAt else { return true }
        let elapsed = now.timeIntervalSince(lastUploadedAt)
        guard elapsed >= 0 else { return false }

        let distance = RideStatisticsCalculator.distance(
            from: lastUploadedPoint,
            to: candidate
        )
        let reportedSpeed = max(candidate.speedMetersPerSecond ?? 0, 0)
        let calculatedSpeed = elapsed > 0 ? distance / elapsed : 0
        let isMoving = max(reportedSpeed, calculatedSpeed) >= 1.5

        if isMoving {
            guard elapsed >= minimumMovingIntervalSeconds else { return false }
            return distance >= minimumMovingDistanceMeters
                || elapsed >= maximumMovingIntervalSeconds
        }

        guard elapsed >= minimumStationaryIntervalSeconds else { return false }
        return distance >= minimumStationaryDistanceMeters
            || elapsed >= stationaryHeartbeatIntervalSeconds
    }

    public mutating func markUploaded(
        _ point: RidePoint,
        at date: Date = Date()
    ) {
        lastUploadedPoint = point
        lastUploadedAt = date
    }

    public mutating func reset() {
        lastUploadedPoint = nil
        lastUploadedAt = nil
    }
}
