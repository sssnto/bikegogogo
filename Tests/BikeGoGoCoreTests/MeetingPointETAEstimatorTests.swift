import Testing

@testable import BikeGoGoCore

@Test func meetingPointETAUsesCurrentSpeedFirst() {
    let estimate = MeetingPointETAEstimator.estimate(
        distanceMeters: 3_000,
        currentSpeedMetersPerSecond: 6,
        averageSpeedMetersPerSecond: 4
    )

    #expect(estimate?.durationSeconds == 500)
    #expect(estimate?.source == .currentSpeed)
}

@Test func meetingPointETAFallsBackToAverageSpeed() {
    let estimate = MeetingPointETAEstimator.estimate(
        distanceMeters: 1_800,
        currentSpeedMetersPerSecond: 0.5,
        averageSpeedMetersPerSecond: 5
    )

    #expect(estimate?.durationSeconds == 360)
    #expect(estimate?.source == .averageSpeed)
}

@Test func meetingPointETAWaitsForUsefulSpeed() {
    let estimate = MeetingPointETAEstimator.estimate(
        distanceMeters: 1_000,
        currentSpeedMetersPerSecond: 0.4
    )

    #expect(estimate == nil)
}

@Test func meetingPointETATreatsArrivalAreaAsReached() {
    let estimate = MeetingPointETAEstimator.estimate(
        distanceMeters: 80,
        currentSpeedMetersPerSecond: nil
    )

    #expect(estimate?.durationSeconds == 0)
}
