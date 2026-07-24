import Foundation
import Testing

@testable import BikeGoGoCore

@Test func calculatesDistanceAndSpeed() {
    let start = Date(timeIntervalSince1970: 0)
    let points = [
        RidePoint(latitude: 31.2304, longitude: 121.4737, elevationMeters: 5, timestamp: start),
        RidePoint(latitude: 31.2314, longitude: 121.4747, elevationMeters: 9, timestamp: start.addingTimeInterval(60)),
        RidePoint(latitude: 31.2324, longitude: 121.4757, elevationMeters: 7, timestamp: start.addingTimeInterval(120))
    ]

    let metrics = RideStatisticsCalculator.metrics(for: points)

    #expect(metrics.distanceMeters > 290)
    #expect(metrics.distanceMeters < 310)
    #expect(metrics.elapsedDurationSeconds == 120)
    #expect(metrics.movingDurationSeconds == 120)
    #expect(metrics.elevationGainMeters == 4)
}

@Test func calculatesHeartRateSummary() {
    let start = Date(timeIntervalSince1970: 0)
    let points = [
        RidePoint(latitude: 31.2304, longitude: 121.4737, heartRateBeatsPerMinute: 120, timestamp: start),
        RidePoint(latitude: 31.2314, longitude: 121.4747, heartRateBeatsPerMinute: 130, timestamp: start.addingTimeInterval(60)),
        RidePoint(latitude: 31.2324, longitude: 121.4757, heartRateBeatsPerMinute: 140, timestamp: start.addingTimeInterval(120))
    ]

    let metrics = RideStatisticsCalculator.metrics(for: points)

    #expect(metrics.averageHeartRate == 130)
    #expect(metrics.maxHeartRate == 140)
}

