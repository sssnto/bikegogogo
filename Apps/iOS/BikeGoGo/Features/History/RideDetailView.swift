import BikeGoGoCore
import CoreLocation
import MapKit
import SwiftUI

struct RideDetailView: View {
    @EnvironmentObject private var appState: AppState
    @State private var exportedURL: URL?
    @State private var isExporting = false

    var ride: RideSession

    private var coordinates: [CLLocationCoordinate2D] {
        ride.points.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    private var camera: MapCameraPosition {
        guard let region = MKCoordinateRegion(containing: coordinates) else {
            return .automatic
        }
        return .region(region)
    }

    var body: some View {
        List {
            Section {
                Map(initialPosition: camera) {
                    if coordinates.count > 1 {
                        MapPolyline(coordinates: coordinates)
                            .stroke(.green, lineWidth: 5)
                    }
                }
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .listRowInsets(EdgeInsets())
            }

            Section("统计") {
                metricRow("距离", String(format: "%.2f km", ride.metrics.distanceKilometers))
                metricRow("均速", String(format: "%.1f km/h", ride.metrics.averageSpeedKilometersPerHour))
                metricRow("最高速度", String(format: "%.1f km/h", ride.metrics.maxSpeedKilometersPerHour))
                metricRow("爬升", String(format: "%.0f m", ride.metrics.elevationGainMeters))
                metricRow("移动时间", durationText(ride.metrics.movingDurationSeconds))
                if let heartRate = ride.metrics.averageHeartRate {
                    metricRow("平均心率", "\(heartRate) bpm")
                }
            }

            Section("导出") {
                Button {
                    Task {
                        isExporting = true
                        exportedURL = await appState.exportGPX(for: ride)
                        isExporting = false
                    }
                } label: {
                    Label(isExporting ? "正在生成 GPX" : "生成 GPX 文件", systemImage: "square.and.arrow.up")
                }
                .disabled(isExporting || ride.points.isEmpty)

                if let exportedURL {
                    ShareLink(item: exportedURL) {
                        Label("分享 GPX", systemImage: "doc.badge.arrow.up")
                    }
                }
            }
        }
        .navigationTitle(ride.title)
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3_600
        let minutes = (Int(duration) % 3_600) / 60
        let seconds = Int(duration) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private extension MKCoordinateRegion {
    init?(containing coordinates: [CLLocationCoordinate2D]) {
        guard let first = coordinates.first else {
            return nil
        }

        var minLatitude = first.latitude
        var maxLatitude = first.latitude
        var minLongitude = first.longitude
        var maxLongitude = first.longitude

        for coordinate in coordinates.dropFirst() {
            minLatitude = min(minLatitude, coordinate.latitude)
            maxLatitude = max(maxLatitude, coordinate.latitude)
            minLongitude = min(minLongitude, coordinate.longitude)
            maxLongitude = max(maxLongitude, coordinate.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )

        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLatitude - minLatitude) * 1.4, 0.01),
            longitudeDelta: max((maxLongitude - minLongitude) * 1.4, 0.01)
        )

        self.init(center: center, span: span)
    }
}

