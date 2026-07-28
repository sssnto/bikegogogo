import Foundation
import Testing

@testable import BikeGoGoCore

@Test func liveLocationPolicyUploadsMovingRiderByDistance() {
    let start = Date(timeIntervalSince1970: 1_000)
    let first = point(latitude: 39.9, speed: 5, timestamp: start)
    let moved = point(
        latitude: 39.90025,
        speed: 5,
        timestamp: start.addingTimeInterval(10)
    )
    var policy = LiveLocationUploadPolicy()
    policy.markUploaded(first, at: start)

    #expect(policy.shouldUpload(moved, at: start.addingTimeInterval(10)))
}

@Test func liveLocationPolicyLimitsFrequentMovingUpdates() {
    let start = Date(timeIntervalSince1970: 2_000)
    let first = point(latitude: 39.9, speed: 5, timestamp: start)
    let moved = point(
        latitude: 39.90025,
        speed: 5,
        timestamp: start.addingTimeInterval(4)
    )
    var policy = LiveLocationUploadPolicy()
    policy.markUploaded(first, at: start)

    #expect(!policy.shouldUpload(moved, at: start.addingTimeInterval(4)))
}

@Test func liveLocationPolicyKeepsStationaryHeartbeat() {
    let start = Date(timeIntervalSince1970: 3_000)
    let stationary = point(latitude: 39.9, speed: 0, timestamp: start)
    var policy = LiveLocationUploadPolicy()
    policy.markUploaded(stationary, at: start)

    #expect(!policy.shouldUpload(
        stationary,
        at: start.addingTimeInterval(30)
    ))
    #expect(policy.shouldUpload(
        stationary,
        at: start.addingTimeInterval(46)
    ))
}

@Test func liveLocationPolicyCanForceSafetyUpdate() {
    let start = Date(timeIntervalSince1970: 4_000)
    let stationary = point(latitude: 39.9, speed: 0, timestamp: start)
    var policy = LiveLocationUploadPolicy()
    policy.markUploaded(stationary, at: start)

    #expect(policy.shouldUpload(
        stationary,
        at: start.addingTimeInterval(1),
        force: true
    ))
}

private func point(
    latitude: Double,
    speed: Double,
    timestamp: Date
) -> RidePoint {
    RidePoint(
        latitude: latitude,
        longitude: 116,
        speedMetersPerSecond: speed,
        timestamp: timestamp
    )
}
