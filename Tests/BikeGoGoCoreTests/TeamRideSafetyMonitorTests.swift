import Foundation
import Testing

@testable import BikeGoGoCore

@Test func separationRequiresSustainedDistanceAndRecovers() {
    let start = Date(timeIntervalSince1970: 1_000)
    let rider = RidePoint(
        latitude: 39.9,
        longitude: 116.0,
        timestamp: start
    )
    let farSample = TeamRideLocationSample(
        userID: "rider-2",
        displayName: "Rider 2",
        latitude: 39.9,
        longitude: 116.01,
        updatedAt: start
    )
    var monitor = TeamRideSafetyMonitor()

    let initial = monitor.evaluate(
        riderLocation: rider,
        samples: [farSample],
        now: start
    )
    #expect(initial.statuses.first?.state == .separated)
    #expect(initial.newAlerts.isEmpty)

    let sustained = monitor.evaluate(
        riderLocation: rider,
        samples: [farSample],
        now: start.addingTimeInterval(46)
    )
    #expect(sustained.newAlerts.first?.kind == .separated)

    let repeated = monitor.evaluate(
        riderLocation: rider,
        samples: [farSample],
        now: start.addingTimeInterval(50)
    )
    #expect(repeated.newAlerts.isEmpty)

    let recoveredSample = TeamRideLocationSample(
        userID: "rider-2",
        displayName: "Rider 2",
        latitude: 39.9,
        longitude: 116.001,
        updatedAt: start.addingTimeInterval(51)
    )
    let recovered = monitor.evaluate(
        riderLocation: rider,
        samples: [recoveredSample],
        now: start.addingTimeInterval(51)
    )
    #expect(recovered.statuses.first?.state == .nearby)
}

@Test func staleLocationAlertsOnceUntilItRecovers() {
    let start = Date(timeIntervalSince1970: 2_000)
    let rider = RidePoint(
        latitude: 39.9,
        longitude: 116.0,
        timestamp: start
    )
    let sample = TeamRideLocationSample(
        userID: "rider-3",
        displayName: "Rider 3",
        latitude: 39.9,
        longitude: 116.001,
        updatedAt: start
    )
    var monitor = TeamRideSafetyMonitor()

    _ = monitor.evaluate(
        riderLocation: rider,
        samples: [sample],
        now: start
    )
    let stale = monitor.evaluate(
        riderLocation: rider,
        samples: [],
        now: start.addingTimeInterval(61)
    )
    #expect(stale.statuses.first?.state == .signalLost)
    #expect(stale.newAlerts.first?.kind == .signalLost)

    let repeated = monitor.evaluate(
        riderLocation: rider,
        samples: [],
        now: start.addingTimeInterval(75)
    )
    #expect(repeated.newAlerts.isEmpty)

    let recoveredSample = TeamRideLocationSample(
        userID: "rider-3",
        displayName: "Rider 3",
        latitude: 39.9,
        longitude: 116.001,
        updatedAt: start.addingTimeInterval(76)
    )
    let recovered = monitor.evaluate(
        riderLocation: rider,
        samples: [recoveredSample],
        now: start.addingTimeInterval(76)
    )
    #expect(recovered.statuses.first?.state == .nearby)
}
