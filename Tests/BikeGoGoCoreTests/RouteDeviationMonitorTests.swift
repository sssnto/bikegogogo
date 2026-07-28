import Foundation
import Testing

@testable import BikeGoGoCore

@Test func routeDeviationRequiresSustainedDistanceAndRecovers() {
    let start = Date(timeIntervalSince1970: 1_000)
    let route = [
        RidePoint(latitude: 39.9, longitude: 116.0, timestamp: start),
        RidePoint(latitude: 39.9, longitude: 116.02, timestamp: start)
    ]
    let farAway = RidePoint(
        latitude: 39.902,
        longitude: 116.01,
        timestamp: start
    )
    var monitor = RouteDeviationMonitor()

    let initial = monitor.evaluate(
        riderLocation: farAway,
        referenceRoute: route,
        now: start
    )
    #expect(initial?.state == .checking)
    #expect(initial?.shouldAlert == false)

    let sustained = monitor.evaluate(
        riderLocation: farAway,
        referenceRoute: route,
        now: start.addingTimeInterval(31)
    )
    #expect(sustained?.state == .deviating)
    #expect(sustained?.shouldAlert == true)

    let repeated = monitor.evaluate(
        riderLocation: farAway,
        referenceRoute: route,
        now: start.addingTimeInterval(40)
    )
    #expect(repeated?.shouldAlert == false)

    let recovered = RidePoint(
        latitude: 39.9002,
        longitude: 116.01,
        timestamp: start
    )
    let recovery = monitor.evaluate(
        riderLocation: recovered,
        referenceRoute: route,
        now: start.addingTimeInterval(41)
    )
    #expect(recovery?.state == .onRoute)
    #expect(recovery?.distanceMeters ?? 100 < 80)
}

@Test func routeDistanceUsesTheClosestPolylineSegment() {
    let start = Date(timeIntervalSince1970: 2_000)
    let route = [
        RidePoint(latitude: 39.9, longitude: 116.0, timestamp: start),
        RidePoint(latitude: 39.9, longitude: 116.02, timestamp: start)
    ]
    let nearMiddle = RidePoint(
        latitude: 39.90045,
        longitude: 116.01,
        timestamp: start
    )
    var monitor = RouteDeviationMonitor()

    let evaluation = monitor.evaluate(
        riderLocation: nearMiddle,
        referenceRoute: route,
        now: start
    )

    #expect(evaluation?.state == .onRoute)
    #expect(evaluation?.distanceMeters ?? 100 < 60)
}

@Test func routeDeviationNeedsAtLeastOneReferencePoint() {
    let point = RidePoint(
        latitude: 39.9,
        longitude: 116.0,
        timestamp: Date()
    )
    var monitor = RouteDeviationMonitor()

    #expect(
        monitor.evaluate(
            riderLocation: point,
            referenceRoute: []
        ) == nil
    )
}
