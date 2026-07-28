import BikeGoGoCore
import CoreLocation
import MapKit
import SwiftUI

private let defaultRideMapRegion = MKCoordinateRegion(
    center: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
    span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
)

struct RideTrackingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isConfirmingFinish = false
    @State private var isConfirmingDiscard = false
    @State private var camera = MapCameraPosition.userLocation(
        followsHeading: false,
        fallback: .region(defaultRideMapRegion)
    )

    private var coordinates: [CLLocationCoordinate2D] {
        appState.currentRide.points.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                rideMap

                metricsPanel
                    .padding(16)

                controls
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
            .navigationTitle("BikeGoGo")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if appState.currentRide.state == .idle || appState.currentRide.state == .finished {
                        Button {
                            appState.requestRidePermissions()
                            focusOnCurrentLocation()
                        } label: {
                            Image(systemName: "location.circle.fill")
                        }
                        .accessibilityLabel("定位到我的位置")
                    } else {
                        Button(role: .destructive) {
                            isConfirmingDiscard = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("放弃本次骑行")
                    }
                }
            }
            .confirmationDialog("结束并保存本次骑行？", isPresented: $isConfirmingFinish) {
                Button("结束骑行", role: .destructive) {
                    appState.finishRide()
                }
                Button("继续骑行", role: .cancel) {}
            }
            .confirmationDialog("放弃本次骑行？轨迹将不会保存。", isPresented: $isConfirmingDiscard) {
                Button("放弃骑行", role: .destructive) {
                    appState.discardCurrentRide()
                }
                Button("取消", role: .cancel) {}
            }
            .alert(
                "BikeGoGo",
                isPresented: Binding(
                    get: { appState.rideAlertMessage != nil },
                    set: { if !$0 { appState.rideAlertMessage = nil } }
                )
            ) {
                Button("知道了") {
                    appState.rideAlertMessage = nil
                }
            } message: {
                Text(appState.rideAlertMessage ?? "")
            }
        }
    }

    private var rideMap: some View {
        Map(position: $camera) {
            UserAnnotation()

            ForEach(appState.teammateLocations) { location in
                Annotation(
                    location.user.displayName,
                    coordinate: CLLocationCoordinate2D(
                        latitude: location.latitude,
                        longitude: location.longitude
                    )
                ) {
                    TeammateLocationAnnotation(
                        name: location.user.displayName,
                        speedMetersPerSecond: location.speedMetersPerSecond
                    )
                }
            }

            if coordinates.count > 1 {
                MapPolyline(coordinates: coordinates)
                    .stroke(.green, lineWidth: 5)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
        .overlay(alignment: .topLeading) {
            if let locationStatus {
                Label(locationStatus.text, systemImage: locationStatus.icon)
                    .font(.caption)
                    .foregroundStyle(locationStatus.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(12)
            }
        }
        .overlay(alignment: .topTrailing) {
            locationSharingMenu
                .padding(12)
        }
        .overlay(alignment: .bottomLeading) {
            if appState.isSharingRideLocation {
                Label(
                    locationSharingStatusText,
                    systemImage: appState.locationSharingMessage == nil
                        ? "location.2.fill"
                        : "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(
                    appState.locationSharingMessage == nil ? Color.primary : Color.orange
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(12)
            }
        }
        .onChange(of: coordinates.count) {
            guard let latest = coordinates.last else { return }
            camera = .region(
                MKCoordinateRegion(
                    center: latest,
                    span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                )
            )
        }
        .onChange(of: appState.locationAuthorizationStatus) { _, status in
            guard status == .authorizedAlways || status == .authorizedWhenInUse else {
                return
            }
            focusOnCurrentLocation()
        }
    }

    private func focusOnCurrentLocation() {
        withAnimation(.easeInOut(duration: 0.3)) {
            camera = .userLocation(
                followsHeading: false,
                fallback: .region(defaultRideMapRegion)
            )
        }
    }

    private var locationStatus: (text: String, icon: String, color: Color)? {
        guard appState.currentRide.state == .recording else { return nil }

        if appState.isWaitingForAccurateLocation {
            if let accuracy = appState.locationAccuracyMeters {
                return (
                    "GPS 信号弱 ±\(Int(accuracy.rounded())) m",
                    "location.slash.fill",
                    .orange
                )
            }
            return ("正在获取准确定位", "location.magnifyingglass", .orange)
        }

        guard let accuracy = appState.locationAccuracyMeters else { return nil }
        if accuracy > RideLocationFilter.maximumTrackingHorizontalAccuracyMeters {
            return (
                "GPS 信号弱 ±\(Int(accuracy.rounded())) m",
                "location.slash.fill",
                .orange
            )
        }
        return (
            "定位精度 ±\(Int(accuracy.rounded())) m",
            "location.fill",
            .green
        )
    }

    @ViewBuilder
    private var locationSharingMenu: some View {
        let isActiveRide = appState.currentRide.state == .recording
            || appState.currentRide.state == .paused

        if isActiveRide, !appState.accountClient.groups.isEmpty {
            Menu {
                ForEach(appState.accountClient.groups) { group in
                    Button {
                        Task {
                            await appState.startRideLocationSharing(groupID: group.id)
                        }
                    } label: {
                        Label(
                            group.name,
                            systemImage: appState.locationSharingGroupID == group.id
                                ? "checkmark.circle.fill"
                                : "person.2.fill"
                        )
                    }
                }

                if appState.isSharingRideLocation {
                    Divider()
                    Button(role: .destructive) {
                        Task {
                            await appState.stopRideLocationSharing()
                        }
                    } label: {
                        Label("停止位置共享", systemImage: "location.slash.fill")
                    }
                }
            } label: {
                Image(
                    systemName: appState.isSharingRideLocation
                        ? "location.2.fill"
                        : "location.2"
                )
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel(
                appState.isSharingRideLocation ? "管理小队位置共享" : "开启小队位置共享"
            )
        }
    }

    private var locationSharingStatusText: String {
        if let message = appState.locationSharingMessage {
            return message
        }
        let groupName = appState.activeLocationSharingGroup?.name ?? "小队"
        let teammateCount = appState.teammateLocations.count
        return "\(groupName) · \(teammateCount) 位队友在线"
    }

    private var metricsPanel: some View {
        let metrics = appState.currentRide.metrics

        return TimelineView(.periodic(from: .now, by: 1)) { context in
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    MetricTile(title: "距离", value: String(format: "%.2f km", metrics.distanceKilometers))
                    MetricTile(title: "当前速度", value: String(format: "%.1f km/h", appState.currentSpeedMetersPerSecond * 3.6))
                }

                GridRow {
                    MetricTile(title: "骑行时间", value: durationText(appState.rideElapsedDuration(at: context.date)))
                    MetricTile(title: "平均速度", value: String(format: "%.1f km/h", metrics.averageSpeedKilometersPerHour))
                }

                GridRow {
                    MetricTile(
                        title: "Watch 心率",
                        value: appState.watchHeartRate > 0 ? "\(Int(appState.watchHeartRate)) bpm" : "-- bpm"
                    )
                    MetricTile(title: "累计爬升", value: String(format: "%.0f m", metrics.elevationGainMeters))
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            switch appState.currentRide.state {
            case .idle, .finished:
                Button {
                    appState.startRide()
                } label: {
                    Label("开始骑行", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            case .recording:
                Button {
                    appState.pauseRide()
                } label: {
                    Label("暂停", systemImage: "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button(role: .destructive) {
                    isConfirmingFinish = true
                } label: {
                    Label("结束", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

            case .paused:
                Button {
                    appState.resumeRide()
                } label: {
                    Label("继续", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(role: .destructive) {
                    isConfirmingFinish = true
                } label: {
                    Label("结束", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

private struct TeammateLocationAnnotation: View {
    var name: String
    var speedMetersPerSecond: Double?

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(.blue)
                    .frame(width: 34, height: 34)
                    .shadow(radius: 2, y: 1)
                Image(systemName: "person.fill")
                    .font(.body)
                    .foregroundStyle(.white)
            }

            Text(annotationText)
                .font(.caption2)
                .fontWeight(.semibold)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var annotationText: String {
        guard let speedMetersPerSecond, speedMetersPerSecond >= 0.5 else {
            return name
        }
        return "\(name) \(Int((speedMetersPerSecond * 3.6).rounded())) km/h"
    }
}

private struct MetricTile: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
