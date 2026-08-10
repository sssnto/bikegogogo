import BikeGoGoCore
import Charts
import CoreLocation
import MapKit
import SwiftUI

struct RideDetailView: View {
    @EnvironmentObject private var appState: AppState
    @State private var exportedURL: URL?
    @State private var isExporting = false
    @State private var hasStartedRoutePlayback = false
    @State private var routePlaybackStartedAt: Date?
    @State private var routePlaybackToken = UUID()

    private let initialRide: RideSession

    init(ride: RideSession) {
        initialRide = ride
    }

    private var ride: RideSession {
        appState.recentRides.first { $0.id == initialRide.id } ?? initialRide
    }

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
                AnimatedRideRouteMap(
                    coordinates: coordinates,
                    camera: camera,
                    playbackStartedAt: routePlaybackStartedAt,
                    playbackDuration: routePlaybackDuration,
                    onReplay: startRoutePlayback
                )
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

            if let weather = ride.weather {
                Section("骑行天气") {
                    Label(
                        "\(Int(weather.temperatureCelsius.rounded()))° · \(weather.conditionText)",
                        systemImage: weather.symbolName
                    )
                    if let apparent = weather.apparentTemperatureCelsius {
                        metricRow("体感温度", "\(Int(apparent.rounded()))°")
                    }
                    if let humidity = weather.relativeHumidityPercent {
                        metricRow("相对湿度", "\(Int(humidity.rounded()))%")
                    }
                    if let windSpeed = weather.windSpeedKilometersPerHour {
                        metricRow("风速", weatherWindText(weather, speed: windSpeed))
                    }
                    metricRow(
                        "记录时间",
                        weather.capturedAt.formatted(
                            date: .omitted,
                            time: .shortened
                        )
                    )
                    if let sourceURL = appState.weatherAttributionURL {
                        Link(destination: sourceURL) {
                            Label("Apple 天气数据来源", systemImage: "info.circle")
                        }
                    }
                }
            }

            Section("心率") {
                if heartRateSamples.count > 1 {
                    RideMetricChart(
                        samples: heartRateSamples,
                        unit: "bpm",
                        color: .red
                    )
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("这条记录还没有心率采样", systemImage: "heart.slash")
                            .font(.headline)
                        Text(heartRateUnavailableMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Button {
                            Task {
                                await appState.importHealthKitRides(
                                    since: ride.startedAt.addingTimeInterval(-10 * 60)
                                )
                                await appState.syncRides()
                            }
                        } label: {
                            if appState.isImportingHealthKit {
                                ProgressView("正在读取苹果健身")
                            } else {
                                Label("从苹果健身补全本次数据", systemImage: "heart.text.square")
                            }
                        }
                        .disabled(appState.isImportingHealthKit)

                        if let message = appState.healthKitImportMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
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
        .onAppear {
            guard !hasStartedRoutePlayback else { return }
            hasStartedRoutePlayback = true
            startRoutePlayback()
        }
        .task(id: routePlaybackToken) {
            guard let startedAt = routePlaybackStartedAt else { return }
            let token = routePlaybackToken
            do {
                try await Task.sleep(for: .seconds(routePlaybackDuration))
            } catch {
                return
            }
            guard token == routePlaybackToken,
                  routePlaybackStartedAt == startedAt else { return }
            routePlaybackStartedAt = nil
        }
    }

    private var routePlaybackDuration: TimeInterval {
        AnimatedRideRouteMap.playbackDuration(for: coordinates)
    }

    private func startRoutePlayback() {
        guard coordinates.count > 1 else {
            routePlaybackStartedAt = nil
            return
        }
        routePlaybackStartedAt = Date()
        routePlaybackToken = UUID()
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func weatherWindText(
        _ weather: RideWeatherSnapshot,
        speed: Double
    ) -> String {
        guard let degrees = weather.windDirectionDegrees else {
            return String(format: "%.0f km/h", speed)
        }
        let directions = ["北", "东北", "东", "东南", "南", "西南", "西", "西北"]
        let normalized = degrees.truncatingRemainder(dividingBy: 360)
        let index = Int(((normalized + 22.5) / 45).rounded(.down)) % directions.count
        return String(format: "%@风 %.0f km/h", directions[index], speed)
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

    private var heartRateUnavailableMessage: String {
        switch ride.source {
        case .iPhone:
            "当前是手机记录。若苹果健身中有同一时间的户外单车训练，可以读取 Apple Watch 心率并自动合并。"
        case .appleWatch, .merged:
            "苹果健身没有返回这次训练的心率采样，请检查 BikeGoGo 的健康读取权限。"
        }
    }
}

private struct AnimatedRideRouteMap: View {
    let coordinates: [CLLocationCoordinate2D]
    let camera: MapCameraPosition
    let playbackStartedAt: Date?
    let playbackDuration: TimeInterval
    let onReplay: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sampledCoordinates: [CLLocationCoordinate2D] {
        Self.sampledCoordinates(from: coordinates)
    }

    static func playbackDuration(
        for coordinates: [CLLocationCoordinate2D]
    ) -> TimeInterval {
        min(max(Double(sampledCoordinates(from: coordinates).count) / 45, 5), 14)
    }

    private static func sampledCoordinates(
        from coordinates: [CLLocationCoordinate2D]
    ) -> [CLLocationCoordinate2D] {
        guard coordinates.count > 700 else { return coordinates }
        let step = max(coordinates.count / 700, 1)
        var sampled = coordinates.enumerated().compactMap { index, coordinate in
            index.isMultiple(of: step) ? coordinate : nil
        }
        if let last = coordinates.last,
           sampled.last?.latitude != last.latitude
            || sampled.last?.longitude != last.longitude {
            sampled.append(last)
        }
        return sampled
    }

    var body: some View {
        TimelineView(.animation(
            minimumInterval: 1 / 24,
            paused: playbackStartedAt == nil
        )) { context in
            let progress = reduceMotion ? 1 : playbackStartedAt.map {
                min(max(context.date.timeIntervalSince($0) / playbackDuration, 0), 1)
            } ?? 1
            let visibleCoordinates = coordinates(through: progress)

            Map(initialPosition: camera) {
                if visibleCoordinates.count > 1 {
                    MapPolyline(coordinates: visibleCoordinates)
                        .stroke(
                            Color(red: 0.10, green: 0.78, blue: 0.38),
                            style: StrokeStyle(
                                lineWidth: 6,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                }

                if let coordinate = visibleCoordinates.last {
                    Annotation("", coordinate: coordinate) {
                        CartoonCyclistMarker(isMoving: progress < 1)
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                Button(action: onReplay) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.headline)
                        .frame(width: 42, height: 42)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(10)
                .accessibilityLabel("重播骑行轨迹")
                .help("重播骑行轨迹")
            }
        }
    }

    private func coordinates(through progress: Double) -> [CLLocationCoordinate2D] {
        guard sampledCoordinates.count > 1 else { return sampledCoordinates }
        let position = progress * Double(sampledCoordinates.count - 1)
        let completedIndex = min(Int(position.rounded(.down)), sampledCoordinates.count - 1)
        var result = Array(sampledCoordinates.prefix(completedIndex + 1))
        guard completedIndex + 1 < sampledCoordinates.count else { return result }

        let fraction = position - Double(completedIndex)
        let start = sampledCoordinates[completedIndex]
        let end = sampledCoordinates[completedIndex + 1]
        result.append(CLLocationCoordinate2D(
            latitude: start.latitude + (end.latitude - start.latitude) * fraction,
            longitude: start.longitude + (end.longitude - start.longitude) * fraction
        ))
        return result
    }
}

private struct CartoonCyclistMarker: View {
    let isMoving: Bool
    @State private var pedalPulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.05, green: 0.45, blue: 0.40))
            Circle()
                .stroke(.white, lineWidth: 3)
            Image(systemName: "figure.outdoor.cycle")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.white)
                .scaleEffect(isMoving && pedalPulse ? 1.10 : 0.96)
        }
        .frame(width: 42, height: 42)
        .shadow(color: .black.opacity(0.28), radius: 5, y: 3)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.34).repeatForever(autoreverses: true)) {
                pedalPulse = true
            }
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
