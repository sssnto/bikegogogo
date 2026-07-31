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

@Test func liveLocationPolicyQuicklyPublishesCorrectedGPSFix() {
    let start = Date(timeIntervalSince1970: 5_000)
    let initial = point(
        latitude: 39.9,
        speed: 0,
        accuracy: 12,
        timestamp: start
    )
    let corrected = point(
        latitude: 39.9003,
        speed: 0,
        accuracy: 8,
        timestamp: start.addingTimeInterval(6)
    )
    var policy = LiveLocationUploadPolicy()
    policy.markUploaded(initial, at: start)

    #expect(policy.shouldUpload(
        corrected,
        at: start.addingTimeInterval(6)
    ))
}

@Test func liveLocationPolicyIgnoresSmallStationaryJitter() {
    let start = Date(timeIntervalSince1970: 6_000)
    let initial = point(
        latitude: 39.9,
        speed: 0,
        accuracy: 8,
        timestamp: start
    )
    let jitter = point(
        latitude: 39.90005,
        speed: 0,
        accuracy: 8,
        timestamp: start.addingTimeInterval(6)
    )
    var policy = LiveLocationUploadPolicy()
    policy.markUploaded(initial, at: start)

    #expect(!policy.shouldUpload(
        jitter,
        at: start.addingTimeInterval(6)
    ))
}

private func point(
    latitude: Double,
    speed: Double,
    accuracy: Double? = nil,
    timestamp: Date
) -> RidePoint {
    RidePoint(
        latitude: latitude,
        longitude: 116,
        speedMetersPerSecond: speed,
        horizontalAccuracyMeters: accuracy,
        timestamp: timestamp
    )
}
