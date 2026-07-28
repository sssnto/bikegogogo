import Foundation

public struct TeamRideLocationSample: Equatable, Sendable {
    public let userID: String
    public let displayName: String
    public let latitude: Double
    public let longitude: Double
    public let updatedAt: Date

    public init(
        userID: String,
        displayName: String,
        latitude: Double,
        longitude: Double,
        updatedAt: Date
    ) {
        self.userID = userID
        self.displayName = displayName
        self.latitude = latitude
        self.longitude = longitude
        self.updatedAt = updatedAt
    }
}

public enum TeamRideMemberState: String, Equatable, Sendable {
    case nearby
    case separated
    case signalLost
}

public struct TeamRideMemberStatus: Identifiable, Equatable, Sendable {
    public let userID: String
    public let displayName: String
    public let state: TeamRideMemberState
    public let distanceMeters: Double?
    public let secondsSinceUpdate: TimeInterval

    public var id: String { userID }
}

public enum TeamRideSafetyAlertKind: Equatable, Sendable {
    case separated
    case signalLost
}

public struct TeamRideSafetyAlert: Equatable, Sendable {
    public let userID: String
    public let displayName: String
    public let kind: TeamRideSafetyAlertKind
    public let distanceMeters: Double?
}

public struct TeamRideSafetyEvaluation: Equatable, Sendable {
    public let statuses: [TeamRideMemberStatus]
    public let newAlerts: [TeamRideSafetyAlert]
}

public struct TeamRideSafetyMonitor: Sendable {
    public static let separationDistanceMeters = 500.0
    public static let recoveryDistanceMeters = 350.0
    public static let separationDurationSeconds: TimeInterval = 45
    public static let signalLostAfterSeconds: TimeInterval = 60

    private var knownSamples: [String: TeamRideLocationSample] = [:]
    private var separationStartedAt: [String: Date] = [:]
    private var separatedAlertedUserIDs: Set<String> = []
    private var signalLostAlertedUserIDs: Set<String> = []

    public init() {}

    public mutating func evaluate(
        riderLocation: RidePoint,
        samples: [TeamRideLocationSample],
        now: Date = Date()
    ) -> TeamRideSafetyEvaluation {
        for sample in samples {
            if let existing = knownSamples[sample.userID],
               existing.updatedAt > sample.updatedAt {
                continue
            }
            knownSamples[sample.userID] = sample
        }

        var statuses: [TeamRideMemberStatus] = []
        var alerts: [TeamRideSafetyAlert] = []

        for sample in knownSamples.values {
            let age = max(now.timeIntervalSince(sample.updatedAt), 0)
            if age >= Self.signalLostAfterSeconds {
                statuses.append(
                    TeamRideMemberStatus(
                        userID: sample.userID,
                        displayName: sample.displayName,
                        state: .signalLost,
                        distanceMeters: nil,
                        secondsSinceUpdate: age
                    )
                )
                separationStartedAt.removeValue(forKey: sample.userID)
                separatedAlertedUserIDs.remove(sample.userID)
                if signalLostAlertedUserIDs.insert(sample.userID).inserted {
                    alerts.append(
                        TeamRideSafetyAlert(
                            userID: sample.userID,
                            displayName: sample.displayName,
                            kind: .signalLost,
                            distanceMeters: nil
                        )
                    )
                }
                continue
            }

            signalLostAlertedUserIDs.remove(sample.userID)
            let teammatePoint = RidePoint(
                latitude: sample.latitude,
                longitude: sample.longitude,
                timestamp: sample.updatedAt
            )
            let distance = RideStatisticsCalculator.distance(
                from: riderLocation,
                to: teammatePoint
            )

            if distance > Self.separationDistanceMeters {
                let startedAt = separationStartedAt[sample.userID] ?? now
                separationStartedAt[sample.userID] = startedAt
                statuses.append(
                    TeamRideMemberStatus(
                        userID: sample.userID,
                        displayName: sample.displayName,
                        state: .separated,
                        distanceMeters: distance,
                        secondsSinceUpdate: age
                    )
                )
                if now.timeIntervalSince(startedAt)
                    >= Self.separationDurationSeconds,
                   separatedAlertedUserIDs.insert(sample.userID).inserted {
                    alerts.append(
                        TeamRideSafetyAlert(
                            userID: sample.userID,
                            displayName: sample.displayName,
                            kind: .separated,
                            distanceMeters: distance
                        )
                    )
                }
            } else {
                statuses.append(
                    TeamRideMemberStatus(
                        userID: sample.userID,
                        displayName: sample.displayName,
                        state: .nearby,
                        distanceMeters: distance,
                        secondsSinceUpdate: age
                    )
                )
                if distance <= Self.recoveryDistanceMeters {
                    separationStartedAt.removeValue(forKey: sample.userID)
                    separatedAlertedUserIDs.remove(sample.userID)
                }
            }
        }

        statuses.sort {
            let firstSeverity = Self.severity(of: $0.state)
            let secondSeverity = Self.severity(of: $1.state)
            if firstSeverity != secondSeverity {
                return firstSeverity > secondSeverity
            }
            return $0.displayName.localizedCompare($1.displayName) == .orderedAscending
        }
        return TeamRideSafetyEvaluation(statuses: statuses, newAlerts: alerts)
    }

    public mutating func reset() {
        knownSamples.removeAll()
        separationStartedAt.removeAll()
        separatedAlertedUserIDs.removeAll()
        signalLostAlertedUserIDs.removeAll()
    }

    private static func severity(of state: TeamRideMemberState) -> Int {
        switch state {
        case .nearby: 0
        case .separated: 1
        case .signalLost: 2
        }
    }
}
