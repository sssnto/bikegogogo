import Foundation
import Testing

@testable import BikeGoGoCore

@Test func autoPauseRequiresSustainedStop() {
    let start = Date(timeIntervalSince1970: 1_000)
    var monitor = RideAutoPauseMonitor()

    #expect(monitor.observe(
        speedMetersPerSecond: 0.2,
        horizontalAccuracyMeters: 8,
        speedAccuracyMetersPerSecond: 0.5,
        at: start,
        isAutomaticallyPaused: false
    ) == .none)
    #expect(monitor.evaluate(
        at: start.addingTimeInterval(19),
        isAutomaticallyPaused: false
    ) == .none)
    #expect(monitor.evaluate(
        at: start.addingTimeInterval(20),
        isAutomaticallyPaused: false
    ) == .pause)
}

@Test func movementCancelsPendingAutoPause() {
    let start = Date(timeIntervalSince1970: 1_000)
    var monitor = RideAutoPauseMonitor()
    _ = monitor.observe(
        speedMetersPerSecond: 0,
        horizontalAccuracyMeters: 8,
        speedAccuracyMetersPerSecond: 0.5,
        at: start,
        isAutomaticallyPaused: false
    )

    #expect(monitor.observe(
        speedMetersPerSecond: 4,
        horizontalAccuracyMeters: 8,
        speedAccuracyMetersPerSecond: 0.5,
        at: start.addingTimeInterval(10),
        isAutomaticallyPaused: false
    ) == .none)
    #expect(monitor.evaluate(
        at: start.addingTimeInterval(30),
        isAutomaticallyPaused: false
    ) == .none)
}

@Test func autoResumeRequiresSustainedReliableMovement() {
    let start = Date(timeIntervalSince1970: 1_000)
    var monitor = RideAutoPauseMonitor()

    #expect(monitor.observe(
        speedMetersPerSecond: 2,
        horizontalAccuracyMeters: 8,
        speedAccuracyMetersPerSecond: 0.5,
        at: start,
        isAutomaticallyPaused: true
    ) == .none)
    #expect(monitor.observe(
        speedMetersPerSecond: 2.2,
        horizontalAccuracyMeters: 8,
        speedAccuracyMetersPerSecond: 0.5,
        at: start.addingTimeInterval(5),
        isAutomaticallyPaused: true
    ) == .resume)
}

@Test func inaccurateGPSDoesNotTriggerAutoPauseOrResume() {
    let start = Date(timeIntervalSince1970: 1_000)
    var monitor = RideAutoPauseMonitor()

    #expect(monitor.observe(
        speedMetersPerSecond: 0,
        horizontalAccuracyMeters: 80,
        speedAccuracyMetersPerSecond: 0.5,
        at: start,
        isAutomaticallyPaused: false
    ) == .none)
    #expect(monitor.pauseDeadline == nil)

    #expect(monitor.observe(
        speedMetersPerSecond: 8,
        horizontalAccuracyMeters: 8,
        speedAccuracyMetersPerSecond: 8,
        at: start,
        isAutomaticallyPaused: true
    ) == .none)
}
