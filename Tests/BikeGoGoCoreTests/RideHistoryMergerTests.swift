import Foundation
import Testing

@testable import BikeGoGoCore

@Test func mergesMatchingHealthKitWorkoutWithoutDuplicatingRide() {
    let start = Date(timeIntervalSince1970: 1_000)
    let localID = UUID()
    let local = RideSession(
        id: localID,
        title: "本次骑行",
        state: .finished,
        source: .iPhone,
        startedAt: start,
        endedAt: start.addingTimeInterval(3_600),
        points: [RidePoint(latitude: 39, longitude: 116, timestamp: start)],
        metrics: RideMetrics(distanceMeters: 20_000, elapsedDurationSeconds: 3_600),
        weather: RideWeatherSnapshot(
            temperatureCelsius: 26,
            relativeHumidityPercent: 65,
            conditionText: "晴",
            symbolName: "sun.max.fill",
            capturedAt: start,
            latitude: 39,
            longitude: 116
        )
    )
    let healthKit = RideSession(
        title: "户外单车",
        state: .finished,
        source: .appleWatch,
        startedAt: start.addingTimeInterval(15),
        endedAt: start.addingTimeInterval(3_590),
        metrics: RideMetrics(
            distanceMeters: 20_200,
            elapsedDurationSeconds: 3_575,
            averageHeartRate: 132,
            activeEnergyKilocalories: 510
        )
    )

    let result = RideHistoryMerger.merging(existing: [local], imported: [healthKit])

    #expect(result.count == 1)
    #expect(result[0].id == localID)
    #expect(result[0].source == .merged)
    #expect(result[0].points == local.points)
    #expect(result[0].weather == local.weather)
    #expect(result[0].metrics.averageHeartRate == 132)
    #expect(result[0].metrics.activeEnergyKilocalories == 510)
}

@Test func keepsSeparateCyclingWorkoutsWhenTimesDoNotOverlap() {
    let start = Date(timeIntervalSince1970: 1_000)
    let morning = RideSession(
        title: "早骑",
        state: .finished,
        startedAt: start,
        endedAt: start.addingTimeInterval(1_800),
        metrics: RideMetrics(distanceMeters: 10_000, elapsedDurationSeconds: 1_800)
    )
    let evening = RideSession(
        title: "晚骑",
        state: .finished,
        source: .appleWatch,
        startedAt: start.addingTimeInterval(8 * 3_600),
        endedAt: start.addingTimeInterval(9 * 3_600),
        metrics: RideMetrics(distanceMeters: 18_000, elapsedDurationSeconds: 3_600)
    )

    let result = RideHistoryMerger.merging(existing: [morning], imported: [evening])

    #expect(result.count == 2)
}

@Test func rideWeatherRemainsOptionalForLegacyRideData() throws {
    let ride = RideSession(
        title: "旧骑行",
        state: .finished,
        startedAt: Date(timeIntervalSince1970: 2_000)
    )
    let data = try JSONEncoder().encode(ride)
    let decoded = try JSONDecoder().decode(RideSession.self, from: data)

    #expect(decoded.weather == nil)
}
