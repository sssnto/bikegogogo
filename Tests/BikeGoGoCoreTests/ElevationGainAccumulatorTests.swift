import Testing
@testable import BikeGoGoCore

@Test func elevationGainIgnoresSmallAltitudeNoise() {
    var accumulator = ElevationGainAccumulator()

    for altitude in [100.0, 101.0, 99.5, 101.8, 100.2] {
        accumulator.add(altitudeMeters: altitude, verticalAccuracyMeters: 5)
    }

    #expect(accumulator.elevationGainMeters == 0)
}

@Test func elevationGainTracksMeaningfulClimbsAndResetsAfterDescent() {
    var accumulator = ElevationGainAccumulator()

    accumulator.add(altitudeMeters: 100, verticalAccuracyMeters: 4)
    accumulator.add(altitudeMeters: 104, verticalAccuracyMeters: 4)
    accumulator.add(altitudeMeters: 99, verticalAccuracyMeters: 4)
    accumulator.add(altitudeMeters: 103, verticalAccuracyMeters: 4)

    #expect(accumulator.elevationGainMeters == 8)
}

@Test func elevationGainRejectsVerticallyInaccurateLocations() {
    var accumulator = ElevationGainAccumulator()

    accumulator.add(altitudeMeters: 100, verticalAccuracyMeters: 4)
    accumulator.add(altitudeMeters: 140, verticalAccuracyMeters: 40)
    accumulator.add(altitudeMeters: 104, verticalAccuracyMeters: 4)

    #expect(accumulator.elevationGainMeters == 4)
}
