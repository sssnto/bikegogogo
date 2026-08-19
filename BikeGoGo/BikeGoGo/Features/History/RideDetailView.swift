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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                AnimatedRideRouteMap(
                    coordinates: coordinates,
                    camera: camera,
                    playbackStartedAt: routePlaybackStartedAt,
                    playbackDuration: routePlaybackDuration,
                    onReplay: startRoutePlayback
                )
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: BikeGoGoStyle.cornerRadius))

                rideIdentity

                RideDetailSectionHeader(title: "本次骑行", value: nil)
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    ForEach(primaryMetrics) { metric in
                        RideDetailMetricCard(metric: metric)
                    }
                }

                detailRowsSection(title: "训练数据", rows: performanceRows)

                if let weather = ride.weather {
                    weatherSection(weather)
                }

                VStack(alignment: .leading, spacing: 12) {
                    RideDetailSectionHeader(title: "心率", value: heartRateSummary)

                    if heartRateSamples.count > 1 {
                        RideMetricChart(
                            samples: heartRateSamples,
                            unit: "bpm",
                            color: BikeGoGoStyle.danger
                        )
                    } else {
                        missingHeartRate
                    }
                }
                .padding(16)
                .background(
                    Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: BikeGoGoStyle.cornerRadius)
                )

                if speedSamples.count > 1 {
                    VStack(alignment: .leading, spacing: 12) {
                        RideDetailSectionHeader(
                            title: "速度",
                            value: String(
                                format: "平均 %.1f km/h",
                                ride.metrics.averageSpeedKilometersPerHour
                            )
                        )

                        RideMetricChart(
                            samples: speedSamples,
                            unit: "km/h",
                            color: BikeGoGoStyle.speed
                        )
                    }
                    .padding(16)
                    .background(
                        Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: BikeGoGoStyle.cornerRadius)
                    )
                }

                detailRowsSection(
                    title: "记录信息",
                    rows: [
                        RideDetailRowData(
                            title: "开始时间",
                            value: ChineseDateFormatting.dateTime(ride.startedAt)
                        ),
                        RideDetailRowData(title: "数据来源", value: sourceText)
                    ]
                )

                shareAndExportActions
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(ride.title)
        .navigationBarTitleDisplayMode(.inline)
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

    private var rideIdentity: some View {
        HStack(spacing: 12) {
            Image(systemName: sourceIcon)
                .font(.headline)
                .foregroundStyle(BikeGoGoStyle.brand)
                .frame(width: 44, height: 44)
                .background(
                    BikeGoGoStyle.brand.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: BikeGoGoStyle.cornerRadius)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(ChineseDateFormatting.fullDate(ride.startedAt))
                    .font(.headline)
                Text(
                    "\(ChineseDateFormatting.time(ride.startedAt)) · \(sourceText)"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if let weather = ride.weather {
                Label(
                    "\(Int(weather.temperatureCelsius.rounded()))°",
                    systemImage: weather.symbolName
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BikeGoGoStyle.speed)
            }
        }
    }

    private var primaryMetrics: [RideDetailMetric] {
        var metrics = [
            RideDetailMetric(
                title: "距离",
                value: String(format: "%.2f", ride.metrics.distanceKilometers),
                unit: "km",
                systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                tint: BikeGoGoStyle.brand
            ),
            RideDetailMetric(
                title: "移动时间",
                value: durationText(ride.metrics.movingDurationSeconds),
                unit: nil,
                systemImage: "timer",
                tint: BikeGoGoStyle.warning
            ),
            RideDetailMetric(
                title: "平均速度",
                value: String(
                    format: "%.1f",
                    ride.metrics.averageSpeedKilometersPerHour
                ),
                unit: "km/h",
                systemImage: "speedometer",
                tint: BikeGoGoStyle.speed
            ),
            RideDetailMetric(
                title: "累计爬升",
                value: String(format: "%.0f", ride.metrics.elevationGainMeters),
                unit: "m",
                systemImage: "mountain.2.fill",
                tint: BikeGoGoStyle.route
            ),
            RideDetailMetric(
                title: "最高速度",
                value: String(
                    format: "%.1f",
                    ride.metrics.maxSpeedKilometersPerHour
                ),
                unit: "km/h",
                systemImage: "gauge.with.dots.needle.67percent",
                tint: BikeGoGoStyle.speed
            )
        ]

        if let heartRate = ride.metrics.averageHeartRate {
            metrics.append(RideDetailMetric(
                title: "平均心率",
                value: "\(heartRate)",
                unit: "bpm",
                systemImage: "heart.fill",
                tint: BikeGoGoStyle.danger
            ))
        }
        return metrics
    }

    private var performanceRows: [RideDetailRowData] {
        var rows = [
            RideDetailRowData(
                title: "骑行时间",
                value: durationText(ride.metrics.elapsedDurationSeconds)
            )
        ]
        if let value = ride.metrics.maxHeartRate {
            rows.append(RideDetailRowData(title: "最高心率", value: "\(value) bpm"))
        }
        if let value = ride.metrics.activeEnergyKilocalories {
            rows.append(RideDetailRowData(
                title: "动态热量",
                value: String(format: "%.0f kcal", value)
            ))
        }
        if let value = ride.metrics.totalEnergyKilocalories {
            rows.append(RideDetailRowData(
                title: "总热量",
                value: String(format: "%.0f kcal", value)
            ))
        }
        if let value = ride.metrics.averageCadenceRPM {
            rows.append(RideDetailRowData(
                title: "平均踏频",
                value: String(format: "%.0f rpm", value)
            ))
        }
        if let value = ride.metrics.maxCadenceRPM {
            rows.append(RideDetailRowData(
                title: "最高踏频",
                value: String(format: "%.0f rpm", value)
            ))
        }
        if let value = ride.metrics.averageCyclingPowerWatts {
            rows.append(RideDetailRowData(
                title: "平均功率",
                value: String(format: "%.0f W", value)
            ))
        }
        if let value = ride.metrics.maxCyclingPowerWatts {
            rows.append(RideDetailRowData(
                title: "最高功率",
                value: String(format: "%.0f W", value)
            ))
        }
        return rows
    }

    private var heartRateSummary: String? {
        guard let average = ride.metrics.averageHeartRate else { return nil }
        if let maximum = ride.metrics.maxHeartRate {
            return "平均 \(average) · 最高 \(maximum) bpm"
        }
        return "平均 \(average) bpm"
    }

    private var sourceIcon: String {
        switch ride.source {
        case .iPhone: "iphone"
        case .appleWatch: "applewatch"
        case .merged: "arrow.triangle.merge"
        }
    }

    private var missingHeartRate: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("暂无心率采样", systemImage: "heart.slash")
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
                    Label("从苹果健身补全数据", systemImage: "heart.text.square")
                }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(
                .roundedRectangle(radius: BikeGoGoStyle.cornerRadius)
            )
            .tint(BikeGoGoStyle.brand)
            .disabled(appState.isImportingHealthKit)

            if let message = appState.healthKitImportMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func weatherSection(_ weather: RideWeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            RideDetailSectionHeader(
                title: "骑行天气",
                value: weather.conditionText
            )

            HStack(spacing: 12) {
                RideWeatherMetric(
                    title: "气温",
                    value: "\(Int(weather.temperatureCelsius.rounded()))°",
                    systemImage: weather.symbolName
                )
                if let humidity = weather.relativeHumidityPercent {
                    RideWeatherMetric(
                        title: "湿度",
                        value: "\(Int(humidity.rounded()))%",
                        systemImage: "humidity.fill"
                    )
                }
                if let windSpeed = weather.windSpeedKilometersPerHour {
                    RideWeatherMetric(
                        title: "风况",
                        value: weatherWindText(weather, speed: windSpeed),
                        systemImage: "wind"
                    )
                }
            }

            if let sourceURL = appState.weatherAttributionURL {
                Link(destination: sourceURL) {
                    Label("Apple 天气", systemImage: "info.circle")
                        .font(.caption)
                }
            }
        }
        .padding(16)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: BikeGoGoStyle.cornerRadius)
        )
    }

    private func detailRowsSection(
        title: String,
        rows: [RideDetailRowData]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            RideDetailSectionHeader(title: title, value: nil)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    RideDetailMetricRow(row: row)
                    if index < rows.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: BikeGoGoStyle.cornerRadius)
            )
        }
    }

    private var shareAndExportActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            RideDetailSectionHeader(title: "分享与导出", value: nil)

            NavigationLink {
                RideShareComposerView(ride: ride)
            } label: {
                Label(
                    "制作骑行分享作品",
                    systemImage: "photo.on.rectangle.angled"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(
                .roundedRectangle(radius: BikeGoGoStyle.cornerRadius)
            )
            .tint(BikeGoGoStyle.brand)

            HStack(spacing: 12) {
                Button {
                    Task {
                        isExporting = true
                        exportedURL = await appState.exportGPX(for: ride)
                        isExporting = false
                    }
                } label: {
                    Label(
                        isExporting ? "正在生成" : "生成 GPX",
                        systemImage: "doc.badge.plus"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(
                    .roundedRectangle(radius: BikeGoGoStyle.cornerRadius)
                )
                .disabled(isExporting || ride.points.isEmpty)

                if let exportedURL {
                    ShareLink(item: exportedURL) {
                        Label("分享 GPX", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(
                        .roundedRectangle(radius: BikeGoGoStyle.cornerRadius)
                    )
                }
            }
        }
        .padding(.bottom, 18)
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

    private func weatherWindText(
        _ weather: RideWeatherSnapshot,
        speed: Double
    ) -> String {
        guard let degrees = weather.windDirectionDegrees else {
            return String(format: "%.0f km/h", speed)
        }
        let directions = ["北", "东北", "东", "东南", "南", "西南", "西", "西北"]
        let normalized = degrees.truncatingRemainder(dividingBy: 360)
        let index = Int(
            ((normalized + 22.5) / 45).rounded(.down)
        ) % directions.count
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

private struct RideDetailMetric: Identifiable {
    var id: String { title }
    let title: String
    let value: String
    let unit: String?
    let systemImage: String
    let tint: Color
}

private struct RideDetailRowData {
    let title: String
    let value: String
}

private struct RideDetailSectionHeader: View {
    let title: String
    let value: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
            Spacer()
            if let value {
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct RideDetailMetricCard: View {
    let metric: RideDetailMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(metric.title, systemImage: metric.systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(metric.value)
                    .font(.title2.bold())
                    .monospacedDigit()
                    .foregroundStyle(metric.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                if let unit = metric.unit {
                    Text(unit)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .padding(14)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: BikeGoGoStyle.cornerRadius)
        )
    }
}

private struct RideDetailMetricRow: View {
    let row: RideDetailRowData

    var body: some View {
        HStack {
            Text(row.title)
            Spacer(minLength: 16)
            Text(row.value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 12)
    }
}

private struct RideWeatherMetric: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
