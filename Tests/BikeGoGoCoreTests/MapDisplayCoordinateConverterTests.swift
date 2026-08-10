import Testing

@testable import BikeGoGoCore

@Test func convertsBeijingWGS84ForMainlandMapDisplay() {
    let coordinate = MapDisplayCoordinateConverter.coordinate(
        latitude: 39.908823,
        longitude: 116.397470
    )

    #expect(abs(coordinate.latitude - 39.9102265) < 0.000001)
    #expect(abs(coordinate.longitude - 116.4037136) < 0.000001)
}

@Test func leavesCoordinatesOutsideMainlandChinaUnchanged() {
    let sanFrancisco = MapDisplayCoordinateConverter.coordinate(
        latitude: 37.7749,
        longitude: -122.4194
    )
    let hongKong = MapDisplayCoordinateConverter.coordinate(
        latitude: 22.3193,
        longitude: 114.1694
    )

    #expect(sanFrancisco == MapDisplayCoordinate(
        latitude: 37.7749,
        longitude: -122.4194
    ))
    #expect(hongKong == MapDisplayCoordinate(
        latitude: 22.3193,
        longitude: 114.1694
    ))
}
