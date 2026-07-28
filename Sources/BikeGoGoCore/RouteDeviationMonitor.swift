import Foundation

public enum RouteDeviationState: Equatable, Sendable {
    case onRoute
    case checking
    case deviating
}

public struct RouteDeviationEvaluation: Equatable, Sendable {
    public let state: RouteDeviationState
    public let distanceMeters: Double
    public let shouldAlert: Bool

    public init(
        state: RouteDeviationState,
        distanceMeters: Double,
        shouldAlert: Bool
    ) {
        self.state = state
        self.distanceMeters = distanceMeters
        self.shouldAlert = shouldAlert
    }
}

public struct RouteDeviationMonitor: Sendable {
    public let deviationThresholdMeters: Double
    public let recoveryThresholdMeters: Double
    public let sustainedDurationSeconds: TimeInterval

    private var deviationStartedAt: Date?
    private var hasAlerted = false

    public init(
        deviationThresholdMeters: Double = 150,
        recoveryThresholdMeters: Double = 80,
        sustainedDurationSeconds: TimeInterval = 30
    ) {
        self.deviationThresholdMeters = deviationThresholdMeters
        self.recoveryThresholdMeters = recoveryThresholdMeters
        self.sustainedDurationSeconds = sustainedDurationSeconds
    }

    public mutating func evaluate(
        riderLocation: RidePoint,
        referenceRoute: [RidePoint],
        now: Date = Date()
    ) -> RouteDeviationEvaluation? {
        guard let distance = Self.minimumDistance(
            from: riderLocation,
            to: referenceRoute
        ) else {
            reset()
            return nil
        }

        if distance <= recoveryThresholdMeters {
            reset()
            return RouteDeviationEvaluation(
                state: .onRoute,
                distanceMeters: distance,
                shouldAlert: false
            )
        }

        if hasAlerted {
            return RouteDeviationEvaluation(
                state: .deviating,
                distanceMeters: distance,
                shouldAlert: false
            )
        }

        guard distance > deviationThresholdMeters else {
            deviationStartedAt = nil
            return RouteDeviationEvaluation(
                state: .onRoute,
                distanceMeters: distance,
                shouldAlert: false
            )
        }

        if deviationStartedAt == nil {
            deviationStartedAt = now
        }
        let isSustained = now.timeIntervalSince(deviationStartedAt ?? now)
            >= sustainedDurationSeconds
        if isSustained {
            hasAlerted = true
        }
        return RouteDeviationEvaluation(
            state: isSustained ? .deviating : .checking,
            distanceMeters: distance,
            shouldAlert: isSustained
        )
    }

    public mutating func reset() {
        deviationStartedAt = nil
        hasAlerted = false
    }

    private static func minimumDistance(
        from riderLocation: RidePoint,
        to route: [RidePoint]
    ) -> Double? {
        guard let first = route.first else { return nil }
        guard route.count > 1 else {
            return distance(from: riderLocation, to: first)
        }

        var minimum = Double.greatestFiniteMagnitude
        for index in 1..<route.count {
            minimum = min(
                minimum,
                distance(
                    from: riderLocation,
                    toSegmentFrom: route[index - 1],
                    to: route[index]
                )
            )
        }
        return minimum
    }

    private static func distance(
        from point: RidePoint,
        toSegmentFrom start: RidePoint,
        to end: RidePoint
    ) -> Double {
        let originLatitude = point.latitude * .pi / 180
        let metersPerRadian = 6_371_000.0

        func projected(_ routePoint: RidePoint) -> (x: Double, y: Double) {
            let latitude = routePoint.latitude * .pi / 180
            let longitudeDelta = (routePoint.longitude - point.longitude) * .pi / 180
            return (
                longitudeDelta * cos(originLatitude) * metersPerRadian,
                (latitude - originLatitude) * metersPerRadian
            )
        }

        let startPoint = projected(start)
        let endPoint = projected(end)
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        let squaredLength = dx * dx + dy * dy
        guard squaredLength > 0 else {
            return hypot(startPoint.x, startPoint.y)
        }

        let projection = max(
            0,
            min(1, -(startPoint.x * dx + startPoint.y * dy) / squaredLength)
        )
        return hypot(
            startPoint.x + projection * dx,
            startPoint.y + projection * dy
        )
    }

    private static func distance(
        from first: RidePoint,
        to second: RidePoint
    ) -> Double {
        let latitude1 = first.latitude * .pi / 180
        let latitude2 = second.latitude * .pi / 180
        let latitudeDelta = latitude2 - latitude1
        let longitudeDelta = (second.longitude - first.longitude) * .pi / 180
        let haversine = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(latitude1) * cos(latitude2)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        return 2 * 6_371_000 * asin(min(1, sqrt(haversine)))
    }
}
