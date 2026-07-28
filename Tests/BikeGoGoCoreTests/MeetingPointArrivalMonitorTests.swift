import Foundation
import Testing

@testable import BikeGoGoCore

@Test func meetingPointArrivalRequiresSustainedProximity() {
    let start = Date(timeIntervalSince1970: 1_000)
    let meetingLatitude = 39.9
    let meetingLongitude = 116.0
    let nearby = RidePoint(
        latitude: 39.9005,
        longitude: 116.0,
        timestamp: start
    )
    var monitor = MeetingPointArrivalMonitor()

    let initial = monitor.evaluate(
        riderLocation: nearby,
        meetingPointLatitude: meetingLatitude,
        meetingPointLongitude: meetingLongitude,
        now: start
    )
    #expect(initial.state == .confirming)
    #expect(initial.shouldAlert == false)

    let arrived = monitor.evaluate(
        riderLocation: nearby,
        meetingPointLatitude: meetingLatitude,
        meetingPointLongitude: meetingLongitude,
        now: start.addingTimeInterval(11)
    )
    #expect(arrived.state == .arrived)
    #expect(arrived.shouldAlert == true)

    let repeated = monitor.evaluate(
        riderLocation: nearby,
        meetingPointLatitude: meetingLatitude,
        meetingPointLongitude: meetingLongitude,
        now: start.addingTimeInterval(20)
    )
    #expect(repeated.state == .arrived)
    #expect(repeated.shouldAlert == false)
}

@Test func meetingPointArrivalResetsAfterLeavingTheArea() {
    let start = Date(timeIntervalSince1970: 2_000)
    let meetingLatitude = 39.9
    let meetingLongitude = 116.0
    let nearby = RidePoint(
        latitude: 39.9005,
        longitude: 116.0,
        timestamp: start
    )
    let farAway = RidePoint(
        latitude: 39.902,
        longitude: 116.0,
        timestamp: start
    )
    var monitor = MeetingPointArrivalMonitor(
        sustainedDurationSeconds: 0
    )

    let firstArrival = monitor.evaluate(
        riderLocation: nearby,
        meetingPointLatitude: meetingLatitude,
        meetingPointLongitude: meetingLongitude,
        now: start
    )
    #expect(firstArrival.shouldAlert == true)

    let leftArea = monitor.evaluate(
        riderLocation: farAway,
        meetingPointLatitude: meetingLatitude,
        meetingPointLongitude: meetingLongitude,
        now: start.addingTimeInterval(1)
    )
    #expect(leftArea.state == .approaching)

    let secondArrival = monitor.evaluate(
        riderLocation: nearby,
        meetingPointLatitude: meetingLatitude,
        meetingPointLongitude: meetingLongitude,
        now: start.addingTimeInterval(2)
    )
    #expect(secondArrival.shouldAlert == true)
}

@Test func meetingPointArrivalKeepsHysteresisNearTheBoundary() {
    let start = Date(timeIntervalSince1970: 3_000)
    let meetingLatitude = 39.9
    let meetingLongitude = 116.0
    let nearby = RidePoint(
        latitude: 39.9005,
        longitude: 116.0,
        timestamp: start
    )
    let boundary = RidePoint(
        latitude: 39.9012,
        longitude: 116.0,
        timestamp: start
    )
    var monitor = MeetingPointArrivalMonitor(
        sustainedDurationSeconds: 0
    )

    _ = monitor.evaluate(
        riderLocation: nearby,
        meetingPointLatitude: meetingLatitude,
        meetingPointLongitude: meetingLongitude,
        now: start
    )
    let evaluation = monitor.evaluate(
        riderLocation: boundary,
        meetingPointLatitude: meetingLatitude,
        meetingPointLongitude: meetingLongitude,
        now: start.addingTimeInterval(1)
    )

    #expect(evaluation.state == .arrived)
    #expect(evaluation.shouldAlert == false)
}
