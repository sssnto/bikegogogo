import Foundation
import Testing

@testable import BikeGoGoCore

@Test func waitsForAnAccurateInitialLocation() {
    let start = Date(timeIntervalSince1970: 0)
    var filter = RideLocationFilter()

    let inaccurateResult = filter.accepts(
        point(longitude: 116.0, accuracy: 35, timestamp: start)
    )
    let accurateResult = filter.accepts(
        point(longitude: 116.0, accuracy: 8, timestamp: start)
    )

    #expect(!inaccurateResult)
    #expect(accurateResult)
}

@Test func rejectsMovementWithinLocationUncertainty() {
    let start = Date(timeIntervalSince1970: 0)
    var filter = RideLocationFilter()

    let initialResult = filter.accepts(
        point(longitude: 116.0, accuracy: 10, timestamp: start)
    )
    let jitterResult = filter.accepts(
        point(
            longitude: 116.00005,
            accuracy: 12,
            speed: 0,
            timestamp: start.addingTimeInterval(5)
        )
    )

    #expect(initialResult)
    #expect(!jitterResult)
}

@Test func acceptsPlausibleCyclingMovement() {
    let start = Date(timeIntervalSince1970: 0)
    var filter = RideLocationFilter()

    let initialResult = filter.accepts(
        point(longitude: 116.0, accuracy: 8, timestamp: start)
    )
    let movementResult = filter.accepts(
        point(
            longitude: 116.0003,
            accuracy: 8,
            speed: 5,
            timestamp: start.addingTimeInterval(6)
        )
    )

    #expect(initialResult)
    #expect(movementResult)
}

@Test func rejectsAnImplausibleLocationJump() {
    let start = Date(timeIntervalSince1970: 0)
    var filter = RideLocationFilter()

    let initialResult = filter.accepts(
        point(longitude: 116.0, accuracy: 8, timestamp: start)
    )
    let jumpResult = filter.accepts(
        point(
            longitude: 116.01,
            accuracy: 8,
            speed: 0,
            timestamp: start.addingTimeInterval(5)
        )
    )

    #expect(initialResult)
    #expect(!jumpResult)
}

private func point(
    longitude: Double,
    accuracy: Double,
    speed: Double? = nil,
    timestamp: Date
) -> RidePoint {
    RidePoint(
        latitude: 39.9,
        longitude: longitude,
        speedMetersPerSecond: speed,
        horizontalAccuracyMeters: accuracy,
        timestamp: timestamp
    )
}
