import Foundation

public enum MeetingPointArrivalState: Equatable, Sendable {
    case approaching
    case confirming
    case arrived
}

public struct MeetingPointArrivalEvaluation: Equatable, Sendable {
    public let state: MeetingPointArrivalState
    public let distanceMeters: Double
    public let shouldAlert: Bool

    public init(
        state: MeetingPointArrivalState,
        distanceMeters: Double,
        shouldAlert: Bool
    ) {
        self.state = state
        self.distanceMeters = distanceMeters
        self.shouldAlert = shouldAlert
    }
}

public struct MeetingPointArrivalMonitor: Sendable {
    public let arrivalThresholdMeters: Double
    public let resetThresholdMeters: Double
    public let sustainedDurationSeconds: TimeInterval

    private var arrivalStartedAt: Date?
    private var hasAlerted = false

    public init(
        arrivalThresholdMeters: Double = 100,
        resetThresholdMeters: Double = 180,
        sustainedDurationSeconds: TimeInterval = 10
    ) {
        self.arrivalThresholdMeters = arrivalThresholdMeters
        self.resetThresholdMeters = resetThresholdMeters
        self.sustainedDurationSeconds = sustainedDurationSeconds
    }

    public mutating func evaluate(
        riderLocation: RidePoint,
        meetingPointLatitude: Double,
        meetingPointLongitude: Double,
        now: Date = Date()
    ) -> MeetingPointArrivalEvaluation {
        let distance = Self.distance(
            latitude: riderLocation.latitude,
            longitude: riderLocation.longitude,
            otherLatitude: meetingPointLatitude,
            otherLongitude: meetingPointLongitude
        )

        if distance > resetThresholdMeters {
            reset()
            return MeetingPointArrivalEvaluation(
                state: .approaching,
                distanceMeters: distance,
                shouldAlert: false
            )
        }

        if hasAlerted {
            return MeetingPointArrivalEvaluation(
                state: .arrived,
                distanceMeters: distance,
                shouldAlert: false
            )
        }

        guard distance <= arrivalThresholdMeters else {
            arrivalStartedAt = nil
            return MeetingPointArrivalEvaluation(
                state: .approaching,
                distanceMeters: distance,
                shouldAlert: false
            )
        }

        if arrivalStartedAt == nil {
            arrivalStartedAt = now
        }
        let isSustained = now.timeIntervalSince(arrivalStartedAt ?? now)
            >= sustainedDurationSeconds
        if isSustained {
            hasAlerted = true
        }
        return MeetingPointArrivalEvaluation(
            state: isSustained ? .arrived : .confirming,
            distanceMeters: distance,
            shouldAlert: isSustained
        )
    }

    public mutating func reset() {
        arrivalStartedAt = nil
        hasAlerted = false
    }

    private static func distance(
        latitude: Double,
        longitude: Double,
        otherLatitude: Double,
        otherLongitude: Double
    ) -> Double {
        let latitude1 = latitude * .pi / 180
        let latitude2 = otherLatitude * .pi / 180
        let latitudeDelta = latitude2 - latitude1
        let longitudeDelta = (otherLongitude - longitude) * .pi / 180
        let haversine = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(latitude1) * cos(latitude2)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        return 2 * 6_371_000 * asin(min(1, sqrt(haversine)))
    }
}
