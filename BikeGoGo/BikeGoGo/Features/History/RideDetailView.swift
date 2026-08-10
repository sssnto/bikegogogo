import BikeGoGoCore
import Charts
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
            mapDisplayCoordinate(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    private var camera: MapCameraPosition {
        guard let region = MKCoordinateRegion(containing: coordinates) else {
            return .automatic
        }
        return .region(region)
    }

    private var heartRateSamples: [RideChartSample] {
        ride.points.enumerated().compactMap { index, point in
            guard let value = point.heartRateBeatsPerMinute else { return nil }
            return RideChartSample(id: index, timestamp: point.timestamp, value: Double(value))
        }
    }

    private var speedSamples: [RideChartSample] {
        ride.points.enumerated().compactMap { index, point in
            guard let value = point.speedMetersPerSecond, value >= 0 else { return nil }
            return RideChartSample(id: index, timestamp: point.timestamp, value: value * 3.6)
        }
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
                metricRow("骑行时间", durationText(ride.metrics.elapsedDurationSeconds))
                metricRow("移动时间", durationText(ride.metrics.movingDurationSeconds))
                if let heartRate = ride.metrics.averageHeartRate {
                    metricRow("平均心率", "\(heartRate) bpm")
                }
                if let heartRate = ride.metrics.maxHeartRate {
                    metricRow("最高心率", "\(heartRate) bpm")
                }
                if let energy = ride.metrics.activeEnergyKilocalories {
                    metricRow("动态热量", String(format: "%.0f kcal", energy))
                }
                if let energy = ride.metrics.totalEnergyKilocalories {
                    metricRow("总热量", String(format: "%.0f kcal", energy))
                }
                if let cadence = ride.metrics.averageCadenceRPM {
                    metricRow("平均踏频", String(format: "%.0f rpm", cadence))
                }
                if let cadence = ride.metrics.maxCadenceRPM {
                    metricRow("最高踏频", String(format: "%.0f rpm", cadence))
                }
                if let power = ride.metrics.averageCyclingPowerWatts {
                    metricRow("平均功率", String(format: "%.0f W", power))
                }
                if let power = ride.metrics.maxCyclingPowerWatts {
                    metricRow("最高功率", String(format: "%.0f W", power))
                }
            }

            if heartRateSamples.count > 1 {
                Section("心率") {
                    RideMetricChart(
                        samples: heartRateSamples,
                        unit: "bpm",
                        color: .red
                    )
                }
            }

            if speedSamples.count > 1 {
                Section("速度") {
                    RideMetricChart(
                        samples: speedSamples,
                        unit: "km/h",
                        color: .cyan
                    )
                }
            }

            Section("记录") {
                metricRow("开始时间", ride.startedAt.formatted(date: .abbreviated, time: .shortened))
                metricRow("数据来源", sourceText)
            }

            Section("分享") {
                NavigationLink {
                    RideShareComposerView(ride: ride)
                } label: {
                    Label("制作骑行分享作品", systemImage: "photo.on.rectangle.angled")
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

    private var sourceText: String {
        switch ride.source {
        case .iPhone:
            "BikeGoGo iPhone"
        case .appleWatch:
            "Apple Watch / 苹果健身"
        case .merged:
            "Apple Watch + BikeGoGo"
        }
    }
}

private struct RideChartSample: Identifiable {
    let id: Int
    let timestamp: Date
    let value: Double
}

private struct RideMetricChart: View {
    let samples: [RideChartSample]
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(format: "平均 %.0f %@", average, unit))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                Spacer()
                Text(String(format: "%.0f–%.0f %@", minimum, maximum, unit))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Chart(samples) { sample in
                LineMark(
                    x: .value("时间", sample.timestamp),
                    y: .value(unit, sample.value)
                )
                .foregroundStyle(color)
                .interpolationMethod(.catmullRom)
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 150)
        }
        .padding(.vertical, 6)
    }

    private var average: Double {
        samples.map(\.value).reduce(0, +) / Double(samples.count)
    }

    private var minimum: Double {
        samples.map(\.value).min() ?? 0
    }

    private var maximum: Double {
        samples.map(\.value).max() ?? 0
    }
}

private func mapDisplayCoordinate(
    latitude: Double,
    longitude: Double
) -> CLLocationCoordinate2D {
    let coordinate = MapDisplayCoordinateConverter.coordinate(
        latitude: latitude,
        longitude: longitude
    )
    return CLLocationCoordinate2D(
        latitude: coordinate.latitude,
        longitude: coordinate.longitude
    )
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
