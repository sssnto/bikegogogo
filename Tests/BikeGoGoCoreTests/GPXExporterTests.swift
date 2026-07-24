import Foundation
import Testing

@testable import BikeGoGoCore

@Test func exportsGPXTrackPoints() {
    let start = Date(timeIntervalSince1970: 1_785_000_000)
    let ride = RideSession(
        title: "滨江 <晨骑>",
        state: .finished,
        startedAt: start,
        points: [
            RidePoint(
                latitude: 31.2304,
                longitude: 121.4737,
                elevationMeters: 8,
                speedMetersPerSecond: 6.5,
                heartRateBeatsPerMinute: 128,
                timestamp: start
            )
        ]
    )

    let gpx = GPXExporter.document(for: ride)

    #expect(gpx.contains("<gpx version=\"1.1\""))
    #expect(gpx.contains("<name>滨江 &lt;晨骑&gt;</name>"))
    #expect(gpx.contains("<trkpt lat=\"31.2304\" lon=\"121.4737\">"))
    #expect(gpx.contains("<ele>8.0</ele>"))
    #expect(gpx.contains("<gpxdata:speed>6.5</gpxdata:speed>"))
    #expect(gpx.contains("<gpxdata:hr>128</gpxdata:hr>"))
}

@Test func createsStableSuggestedFilename() {
    let ride = RideSession(
        title: "浦东滨江 轻松骑!",
        startedAt: Date(timeIntervalSince1970: 1_785_000_000)
    )

    let filename = GPXExporter.suggestedFilename(for: ride)

    #expect(filename.hasSuffix("-浦东滨江-轻松骑.gpx"))
}

