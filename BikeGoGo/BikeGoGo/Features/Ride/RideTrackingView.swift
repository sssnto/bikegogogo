import BikeGoGoCore
import CoreLocation
import MapKit
import SwiftUI

private let defaultRideMapRegion = MKCoordinateRegion(
    center: mapDisplayCoordinate(latitude: 31.2304, longitude: 121.4737),
    span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
)

struct RideTrackingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isConfirmingFinish = false
    @State private var isConfirmingDiscard = false
    @State private var isConfirmingSOS = false
    @State private var selectedSOSGroupID: String?
    @State private var isShowingTeamStatus = false
    @State private var isNamingMeetingPoint = false
    @State private var meetingPointGroupID: String?
    @State private var meetingPointDraft = ""
    @State private var camera = MapCameraPosition.userLocation(
        followsHeading: false,
        fallback: .region(defaultRideMapRegion)
    )

    private var coordinates: [CLLocationCoordinate2D] {
        appState.currentRide.points.map {
            mapDisplayCoordinate(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    private var referenceCoordinates: [CLLocationCoordinate2D] {
        appState.referenceRide?.points.map {
            mapDisplayCoordinate(latitude: $0.latitude, longitude: $0.longitude)
        } ?? []
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
                        Menu {
                            Button("放弃本次骑行", systemImage: "trash", role: .destructive) {
                                isConfirmingDiscard = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("更多骑行操作")
                    }
                }
            }
            .alert("结束骑行？", isPresented: $isConfirmingFinish) {
                Button("结束并保存", role: .destructive) {
                    appState.finishRide()
                }
                Button("继续骑行", role: .cancel) {}
            } message: {
                Text("本次路线和骑行数据将保存到历史记录。")
            }
            .alert("放弃本次骑行？", isPresented: $isConfirmingDiscard) {
                Button("放弃骑行", role: .destructive) {
                    appState.discardCurrentRide()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("本次路线和骑行数据不会保存。")
            }
            .alert("发送小队紧急求助？", isPresented: $isConfirmingSOS) {
                Button("发送 SOS", role: .destructive) {
                    guard let selectedSOSGroupID else { return }
                    Task {
                        await appState.sendTeamSOS(groupID: selectedSOSGroupID)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                if let group = selectedSOSGroup {
                    Text("“\(group.name)”的其他成员将收到提醒和你当前的准确位置。此功能不会联系 110/120 等紧急服务。")
                }
            }
            .alert("设置小队集合点", isPresented: $isNamingMeetingPoint) {
                TextField("例如：公园东门", text: $meetingPointDraft)
                Button("设置") {
                    guard let meetingPointGroupID else { return }
                    Task {
                        await appState.setTeamMeetingPoint(
                            groupID: meetingPointGroupID,
                            title: meetingPointDraft
                        )
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("当前位置将作为集合点，有效期 6 小时。")
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
            .sheet(isPresented: $isShowingTeamStatus) {
                TeamRideStatusSheet()
                    .environmentObject(appState)
            }
            .onAppear {
                if appState.currentRide.state == .idle
                    || appState.currentRide.state == .finished {
                    appState.refreshRideWeather()
                }
            }
        }
    }

    private var rideMap: some View {
        Map(position: $camera) {
            UserAnnotation()

            ForEach(appState.teammateLocations) { location in
                Annotation(
                    location.user.displayName,
                    coordinate: mapDisplayCoordinate(
                        latitude: location.latitude,
                        longitude: location.longitude
                    )
                ) {
                    TeammateLocationAnnotation(
                        name: location.user.displayName,
                        speedMetersPerSecond: location.speedMetersPerSecond,
                        state: teamStatus(for: location.user.id)?.state
                    )
                }
            }

            if let meetingPoint = appState.teamMeetingPoint {
                Annotation(
                    meetingPoint.title,
                    coordinate: mapDisplayCoordinate(
                        latitude: meetingPoint.latitude,
                        longitude: meetingPoint.longitude
                    )
                ) {
                    MeetingPointAnnotation(title: meetingPoint.title)
                }
            }

            if referenceCoordinates.count > 1 {
                MapPolyline(coordinates: referenceCoordinates)
                    .stroke(
                        .blue.opacity(0.8),
                        style: StrokeStyle(
                            lineWidth: 4,
                            lineCap: .round,
                            dash: [8, 6]
                        )
                    )
            }

            if coordinates.count > 1 {
                MapPolyline(coordinates: coordinates)
                    .stroke(.green, lineWidth: 5)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 6) {
                if let locationStatus {
                    Label(locationStatus.text, systemImage: locationStatus.icon)
                        .foregroundStyle(locationStatus.color)
                }
                weatherStatus
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(12)
        }
        .overlay(alignment: .topTrailing) {
            rideMapActions
                .padding(12)
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 6) {
                if let meetingPointStatus,
                   let meetingPoint = appState.teamMeetingPoint {
                    Button {
                        focusOnMeetingPoint(meetingPoint)
                    } label: {
                        Label(
                            meetingPointStatus.text,
                            systemImage: meetingPointStatus.icon
                        )
                        .font(.caption)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(meetingPointStatus.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            .regularMaterial,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let routeDeviationStatus {
                    Label(
                        routeDeviationStatus.text,
                        systemImage: routeDeviationStatus.icon
                    )
                    .font(.caption)
                    .foregroundStyle(routeDeviationStatus.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }

                if appState.isSharingRideLocation {
                    Button {
                        isShowingTeamStatus = true
                    } label: {
                        Label(
                            locationSharingStatusText,
                            systemImage: locationSharingStatusIcon
                        )
                        .font(.caption)
                        .foregroundStyle(locationSharingStatusColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
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

    private func teamStatus(for userID: String) -> TeamRideMemberStatus? {
        appState.teamRideMemberStatuses.first { $0.userID == userID }
    }

    private var selectedSOSGroup: AppGroup? {
        guard let selectedSOSGroupID else { return nil }
        return appState.accountClient.groups.first { $0.id == selectedSOSGroupID }
    }

    @ViewBuilder
    private var rideMapActions: some View {
        let isActiveRide = appState.currentRide.state == .recording
            || appState.currentRide.state == .paused
        if isActiveRide {
            HStack(spacing: 8) {
                if !appState.accountClient.groups.isEmpty {
                    teamSOSMenu
                    rideTeamVoiceButton
                }
                rideNavigationMenu
                if !appState.accountClient.groups.isEmpty {
                    locationSharingMenu
                }
            }
        }
    }

    private var teamSOSMenu: some View {
        Menu {
            ForEach(appState.accountClient.groups) { group in
                Button {
                    selectedSOSGroupID = group.id
                    isConfirmingSOS = true
                } label: {
                    Label(group.name, systemImage: "exclamationmark.triangle.fill")
                }
            }
        } label: {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.red)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
        }
        .accessibilityLabel("向小队发送紧急求助")
        .disabled(appState.isSendingTeamSOS)
    }

    @ViewBuilder
    private var rideTeamVoiceButton: some View {
        if appState.hasActiveVoiceCall {
            Menu {
                if appState.voiceClient.isConnected {
                    Button {
                        Task {
                            await appState.toggleMute()
                        }
                    } label: {
                        Label(
                            appState.voiceClient.isMuted ? "打开麦克风" : "静音",
                            systemImage: appState.voiceClient.isMuted
                                ? "mic.fill"
                                : "mic.slash.fill"
                        )
                    }
                }
                Button(role: .destructive) {
                    Task {
                        await appState.leaveVoiceRoom()
                    }
                } label: {
                    Label(
                        appState.voiceCallPhase == .connected ? "结束语音" : "取消呼叫",
                        systemImage: "phone.down.fill"
                    )
                }
            } label: {
                mapActionIcon(
                    rideVoiceStatusIcon,
                    color: rideVoiceStatusColor
                )
            }
            .accessibilityLabel(appState.voiceCallPhase.title)
            .accessibilityValue(appState.voiceCallStatusDetail)
        } else {
            Button {
                Task {
                    await appState.callActiveRideTeam()
                }
            } label: {
                mapActionIcon("phone.fill")
            }
            .accessibilityLabel("呼叫当前小队")
            .disabled(appState.activeLocationSharingGroup == nil)
        }
    }

    private var rideVoiceStatusIcon: String {
        if appState.voiceClient.isMuted {
            return "mic.slash.fill"
        }
        return appState.voiceCallPhase.systemImage
    }

    private var rideVoiceStatusColor: Color {
        switch appState.voiceCallPhase {
        case .connected:
            .green
        case .reconnecting:
            .yellow
        case .idle:
            .primary
        case .preparing, .calling, .connecting, .syncingAudio, .waitingForParticipants:
            .orange
        }
    }

    private var rideNavigationMenu: some View {
        Menu {
            if let group = appState.activeLocationSharingGroup {
                if let meetingPoint = appState.teamMeetingPoint {
                    Button {
                        focusOnMeetingPoint(meetingPoint)
                    } label: {
                        Label("查看集合点", systemImage: "flag.checkered")
                    }
                    Button {
                        openMeetingPointInMaps(meetingPoint)
                    } label: {
                        Label("骑行导航到集合点", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    }
                }
                if group.isOwner {
                    Button {
                        meetingPointGroupID = group.id
                        meetingPointDraft = appState.teamMeetingPoint?.title
                            ?? "小队集合点"
                        isNamingMeetingPoint = true
                    } label: {
                        Label(
                            appState.teamMeetingPoint == nil
                                ? "将当前位置设为集合点"
                                : "更新为当前位置",
                            systemImage: "mappin.and.ellipse"
                        )
                    }
                    if appState.teamMeetingPoint != nil {
                        Button(role: .destructive) {
                            Task {
                                await appState.clearTeamMeetingPoint(groupID: group.id)
                            }
                        } label: {
                            Label("清除集合点", systemImage: "flag.slash")
                        }
                    }
                }
                Divider()
            }

            Menu {
                let candidateRides = appState.recentRides.filter {
                    $0.points.count > 1
                }
                if candidateRides.isEmpty {
                    Text("暂无可用历史路线")
                } else {
                    ForEach(candidateRides.prefix(8)) { ride in
                        Button {
                            appState.selectReferenceRoute(ride)
                        } label: {
                            Label(
                                ride.title,
                                systemImage: appState.referenceRideID == ride.id
                                    ? "checkmark"
                                    : "point.topleft.down.to.point.bottomright.curvepath"
                            )
                        }
                    }
                }
            } label: {
                Label("选择历史参考路线", systemImage: "map")
            }

            if appState.referenceRideID != nil {
                Button(role: .destructive) {
                    appState.clearReferenceRoute()
                } label: {
                    Label("停止路线提醒", systemImage: "map.fill")
                }
            }
        } label: {
            mapActionIcon(
                appState.teamMeetingPoint != nil || appState.referenceRideID != nil
                    ? "map.fill"
                    : "map",
                color: appState.routeDeviationEvaluation?.state == .deviating
                    ? .red
                    : .primary
            )
        }
        .accessibilityLabel("集合点与参考路线")
        .disabled(appState.isUpdatingTeamMeetingPoint)
    }

    private func mapActionIcon(
        _ systemName: String,
        color: Color = .primary
    ) -> some View {
        Image(systemName: systemName)
            .font(.title3)
            .foregroundStyle(color)
            .frame(width: 44, height: 44)
            .background(.regularMaterial, in: Circle())
    }

    private func focusOnCurrentLocation() {
        withAnimation(.easeInOut(duration: 0.3)) {
            camera = .userLocation(
                followsHeading: false,
                fallback: .region(defaultRideMapRegion)
            )
        }
    }

    private func focusOnMeetingPoint(_ meetingPoint: GroupMeetingPoint) {
        withAnimation(.easeInOut(duration: 0.3)) {
            camera = .region(
                MKCoordinateRegion(
                    center: mapDisplayCoordinate(
                        latitude: meetingPoint.latitude,
                        longitude: meetingPoint.longitude
                    ),
                    span: MKCoordinateSpan(
                        latitudeDelta: 0.012,
                        longitudeDelta: 0.012
                    )
                )
            )
        }
    }

    private func openMeetingPointInMaps(_ meetingPoint: GroupMeetingPoint) {
        let mapItem = MKMapItem(
            placemark: MKPlacemark(
                coordinate: mapDisplayCoordinate(
                    latitude: meetingPoint.latitude,
                    longitude: meetingPoint.longitude
                )
            )
        )
        mapItem.name = meetingPoint.title
        mapItem.openInMaps(
            launchOptions: [
                MKLaunchOptionsDirectionsModeKey:
                    MKLaunchOptionsDirectionsModeCycling
            ]
        )
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
    private var weatherStatus: some View {
        let isActiveRide = appState.currentRide.state == .recording
            || appState.currentRide.state == .paused
        let weather = isActiveRide
            ? appState.currentRide.weather ?? appState.currentWeather
            : appState.currentWeather
        if let weather {
            HStack(spacing: 8) {
                Label(
                    "\(Int(weather.temperatureCelsius.rounded()))° · \(weather.conditionText)",
                    systemImage: weather.symbolName
                )
                if let humidity = weather.relativeHumidityPercent {
                    Label("\(Int(humidity.rounded()))%", systemImage: "humidity.fill")
                }
                if let windSpeed = weather.windSpeedKilometersPerHour {
                    Label(
                        String(format: "%.0f km/h", windSpeed),
                        systemImage: "wind"
                    )
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(.primary)

            if let sourceURL = appState.weatherAttributionURL {
                Link(destination: sourceURL) {
                    Text("Apple 天气")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } else if appState.isRefreshingWeather {
            HStack(spacing: 6) {
                ProgressView()
                Text("正在更新天气")
            }
            .foregroundStyle(.secondary)
        } else {
            Button {
                appState.refreshRideWeather()
            } label: {
                Label(
                    appState.weatherMessage ?? "更新天气",
                    systemImage: "cloud.sun"
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
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
                    Toggle(
                        isOn: Binding(
                            get: { appState.teamSafetyAlertsEnabled },
                            set: { appState.setTeamSafetyAlertsEnabled($0) }
                        )
                    ) {
                        Label("掉队与失联提醒", systemImage: "bell.fill")
                    }
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
                        ? "location.fill"
                        : "location"
                )
                .font(.title3)
                .foregroundStyle(
                    appState.isSharingRideLocation ? Color.green : Color.primary
                )
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
        let warningCount = appState.teamRideMemberStatuses.filter {
            $0.state != .nearby
        }.count
        if warningCount > 0 {
            return "\(groupName) · \(warningCount) 项提醒"
        }
        let teammateCount = appState.teammateLocations.count
        return "\(groupName) · \(teammateCount) 位队友在线"
    }

    private var locationSharingStatusIcon: String {
        if appState.locationSharingMessage != nil
            || appState.teamRideMemberStatuses.contains(where: { $0.state != .nearby }) {
            return "exclamationmark.triangle.fill"
        }
        return "location.fill"
    }

    private var locationSharingStatusColor: Color {
        if appState.locationSharingMessage != nil
            || appState.teamRideMemberStatuses.contains(where: { $0.state != .nearby }) {
            return .orange
        }
        return .primary
    }

    private var routeDeviationStatus: (
        text: String,
        icon: String,
        color: Color
    )? {
        guard appState.referenceRideID != nil,
              let evaluation = appState.routeDeviationEvaluation else {
            return nil
        }
        let distance = Int(evaluation.distanceMeters.rounded())
        switch evaluation.state {
        case .onRoute:
            return ("参考路线 · 偏差 \(distance) m", "checkmark.circle.fill", .blue)
        case .checking:
            return ("正在确认路线偏离 · \(distance) m", "location.magnifyingglass", .orange)
        case .deviating:
            return ("已偏离参考路线 · \(distance) m", "exclamationmark.triangle.fill", .red)
        }
    }

    private var meetingPointStatus: (
        text: String,
        icon: String,
        color: Color
    )? {
        guard let meetingPoint = appState.teamMeetingPoint,
              let point = appState.currentReliableLocation else {
            return nil
        }
        let distance = CLLocation(
            latitude: point.latitude,
            longitude: point.longitude
        ).distance(
            from: CLLocation(
                latitude: meetingPoint.latitude,
                longitude: meetingPoint.longitude
            )
        )
        if appState.meetingPointArrivalEvaluation?.state == .arrived {
            return (
                "已到达 · \(meetingPoint.title)",
                "checkmark.circle.fill",
                .green
            )
        }
        let distanceText = distance >= 1_000
            ? String(format: "%.1f km", distance / 1_000)
            : "\(Int(distance.rounded())) m"
        let eta = MeetingPointETAEstimator.estimate(
            distanceMeters: distance,
            currentSpeedMetersPerSecond: point.speedMetersPerSecond,
            averageSpeedMetersPerSecond:
                appState.currentRide.metrics.averageSpeedMetersPerSecond
        )
        let etaText = eta.map {
            " · 约 \(meetingPointDurationText($0.durationSeconds))"
        } ?? ""
        return (
            "\(meetingPoint.title) · \(distanceText)\(etaText)",
            "flag.checkered",
            distance <= 100 ? .green : .orange
        )
    }

    private func meetingPointDurationText(_ duration: TimeInterval) -> String {
        if duration <= 60 {
            return "1 分钟"
        }
        let minutes = Int(ceil(duration / 60))
        if minutes < 60 {
            return "\(minutes) 分钟"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0
            ? "\(hours) 小时"
            : "\(hours) 小时 \(remainingMinutes) 分钟"
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
                    Label("结束骑行", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)

            case .paused:
                Button {
                    appState.resumeRide()
                } label: {
                    Label(
                        appState.isAutomaticallyPaused ? "自动暂停 · 继续" : "继续",
                        systemImage: "play.fill"
                    )
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(role: .destructive) {
                    isConfirmingFinish = true
                } label: {
                    Label("结束骑行", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
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
    var state: TeamRideMemberState?

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(annotationColor)
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

    private var annotationColor: Color {
        switch state {
        case .separated:
            .orange
        case .signalLost:
            .gray
        case .nearby, nil:
            .blue
        }
    }
}

private struct MeetingPointAnnotation: View {
    var title: String

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(.orange)
                    .frame(width: 38, height: 38)
                    .shadow(radius: 2, y: 1)
                Image(systemName: "flag.checkered")
                    .font(.body)
                    .foregroundStyle(.white)
            }
            Text(title)
                .font(.caption2)
                .fontWeight(.semibold)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

private struct MeetingPointMemberProgress: Identifiable {
    let id: String
    let displayName: String
    let distanceMeters: Double?
    let estimatedDurationSeconds: TimeInterval?
    let isCurrentUser: Bool

    var hasArrived: Bool {
        guard let distanceMeters else { return false }
        return distanceMeters <= 100
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

private struct TeamRideStatusSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(
                        "掉队与失联提醒",
                        isOn: Binding(
                            get: { appState.teamSafetyAlertsEnabled },
                            set: { appState.setTeamSafetyAlertsEnabled($0) }
                        )
                    )
                } footer: {
                    Text("距离超过 500 米并持续 45 秒，或位置超过 60 秒未更新时提醒。")
                }

                if let meetingPoint = appState.teamMeetingPoint {
                    Section("小队集合点") {
                        LabeledContent("位置", value: meetingPoint.title)
                        LabeledContent(
                            "距离",
                            value: meetingPointDistanceText(meetingPoint)
                        )
                        LabeledContent(
                            "预计到达",
                            value: meetingPointETAForCurrentUser(meetingPoint)
                        )
                        LabeledContent(
                            "有效期",
                            value: meetingPointExpiryText(meetingPoint)
                        )
                        LabeledContent(
                            "设置人",
                            value: meetingPoint.setBy.displayName
                        )
                        let progress = meetingPointMemberProgress(meetingPoint)
                        if !progress.isEmpty {
                            Divider()
                            LabeledContent(
                                "到达进度",
                                value: "\(progress.filter(\.hasArrived).count) / \(progress.count)"
                            )
                            Text(meetingPointProgressSummary(progress))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(progress) { member in
                                HStack(spacing: 12) {
                                    Image(
                                        systemName: meetingPointIcon(for: member)
                                    )
                                    .foregroundStyle(
                                        meetingPointColor(for: member)
                                    )
                                    .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(
                                            member.isCurrentUser
                                                ? "\(member.displayName)（我）"
                                                : member.displayName
                                        )
                                        Text(meetingPointDetail(for: member))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("本次骑行队友") {
                    if appState.teamRideMemberStatuses.isEmpty {
                        Text("尚未收到队友位置。队友开启同一小队的位置共享后会显示在这里。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appState.teamRideMemberStatuses) { status in
                            HStack(spacing: 12) {
                                Image(systemName: icon(for: status.state))
                                    .foregroundStyle(color(for: status.state))
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(status.displayName)
                                    Text(detail(for: status))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(appState.activeLocationSharingGroup?.name ?? "小队状态")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func icon(for state: TeamRideMemberState) -> String {
        switch state {
        case .nearby: "checkmark.circle.fill"
        case .separated: "exclamationmark.triangle.fill"
        case .signalLost: "wifi.slash"
        }
    }

    private func color(for state: TeamRideMemberState) -> Color {
        switch state {
        case .nearby: .green
        case .separated: .orange
        case .signalLost: .red
        }
    }

    private func detail(for status: TeamRideMemberStatus) -> String {
        switch status.state {
        case .nearby:
            return distanceText(status.distanceMeters)
        case .separated:
            return "距离较远 · \(distanceText(status.distanceMeters))"
        case .signalLost:
            return "位置 \(Int(status.secondsSinceUpdate.rounded())) 秒未更新"
        }
    }

    private func distanceText(_ distance: Double?) -> String {
        guard let distance else { return "距离未知" }
        if distance >= 1_000 {
            return String(format: "%.1f km", distance / 1_000)
        }
        return "\(Int(distance.rounded())) m"
    }

    private func meetingPointDistanceText(
        _ meetingPoint: GroupMeetingPoint
    ) -> String {
        guard let point = appState.currentReliableLocation else {
            return "等待当前位置"
        }
        let riderLocation = CLLocation(
            latitude: point.latitude,
            longitude: point.longitude
        )
        let meetingLocation = CLLocation(
            latitude: meetingPoint.latitude,
            longitude: meetingPoint.longitude
        )
        return distanceText(riderLocation.distance(from: meetingLocation))
    }

    private func meetingPointExpiryText(
        _ meetingPoint: GroupMeetingPoint
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let expiry = formatter.date(from: meetingPoint.expiresAt) else {
            return "6 小时内"
        }
        return expiry.formatted(date: .omitted, time: .shortened)
    }

    private func meetingPointETAForCurrentUser(
        _ meetingPoint: GroupMeetingPoint
    ) -> String {
        guard let point = appState.currentReliableLocation else {
            return "等待当前位置"
        }
        let distance = CLLocation(
            latitude: point.latitude,
            longitude: point.longitude
        ).distance(
            from: CLLocation(
                latitude: meetingPoint.latitude,
                longitude: meetingPoint.longitude
            )
        )
        guard let estimate = MeetingPointETAEstimator.estimate(
            distanceMeters: distance,
            currentSpeedMetersPerSecond: point.speedMetersPerSecond,
            averageSpeedMetersPerSecond:
                appState.currentRide.metrics.averageSpeedMetersPerSecond
        ) else {
            return "开始移动后计算"
        }
        return estimate.durationSeconds == 0
            ? "已到达"
            : "约 \(durationText(estimate.durationSeconds))"
    }

    private func meetingPointMemberProgress(
        _ meetingPoint: GroupMeetingPoint
    ) -> [MeetingPointMemberProgress] {
        guard let group = appState.activeLocationSharingGroup else { return [] }
        let currentUserID = appState.accountClient.currentUser?.id
        return group.members.map { member in
            let isCurrentUser = member.id == currentUserID
            let coordinate: CLLocationCoordinate2D?
            let speedMetersPerSecond: Double?
            let averageSpeedMetersPerSecond: Double?
            if isCurrentUser, let point = appState.currentReliableLocation {
                coordinate = CLLocationCoordinate2D(
                    latitude: point.latitude,
                    longitude: point.longitude
                )
                speedMetersPerSecond = point.speedMetersPerSecond
                averageSpeedMetersPerSecond =
                    appState.currentRide.metrics.averageSpeedMetersPerSecond
            } else if let location = appState.teammateLocations.first(
                where: { $0.user.id == member.id }
            ) {
                coordinate = CLLocationCoordinate2D(
                    latitude: location.latitude,
                    longitude: location.longitude
                )
                speedMetersPerSecond = location.speedMetersPerSecond
                averageSpeedMetersPerSecond = nil
            } else {
                coordinate = nil
                speedMetersPerSecond = nil
                averageSpeedMetersPerSecond = nil
            }
            let distance = coordinate.map {
                CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                    .distance(
                        from: CLLocation(
                            latitude: meetingPoint.latitude,
                            longitude: meetingPoint.longitude
                        )
                    )
            }
            let estimatedDuration = distance.flatMap {
                MeetingPointETAEstimator.estimate(
                    distanceMeters: $0,
                    currentSpeedMetersPerSecond: speedMetersPerSecond,
                    averageSpeedMetersPerSecond: averageSpeedMetersPerSecond
                )?.durationSeconds
            }
            return MeetingPointMemberProgress(
                id: member.id,
                displayName: member.displayName,
                distanceMeters: distance,
                estimatedDurationSeconds: estimatedDuration,
                isCurrentUser: isCurrentUser
            )
        }
        .sorted {
            if $0.isCurrentUser != $1.isCurrentUser {
                return $0.isCurrentUser
            }
            if $0.hasArrived != $1.hasArrived {
                return $0.hasArrived
            }
            return $0.displayName.localizedCompare($1.displayName)
                == .orderedAscending
        }
    }

    private func meetingPointIcon(
        for member: MeetingPointMemberProgress
    ) -> String {
        if member.distanceMeters == nil {
            return "location.slash"
        }
        return member.hasArrived
            ? "checkmark.circle.fill"
            : member.estimatedDurationSeconds == nil
                ? "pause.circle.fill"
                : "arrow.forward.circle.fill"
    }

    private func meetingPointColor(
        for member: MeetingPointMemberProgress
    ) -> Color {
        if member.distanceMeters == nil {
            return .gray
        }
        return member.hasArrived ? .green : .orange
    }

    private func meetingPointDetail(
        for member: MeetingPointMemberProgress
    ) -> String {
        guard let distance = member.distanceMeters else {
            return "未共享本次位置"
        }
        if member.hasArrived {
            return "已到达 · \(distanceText(distance))"
        }
        let etaText = member.estimatedDurationSeconds.map {
            " · 约 \(durationText($0))"
        } ?? " · 等待移动"
        return "距集合点 \(distanceText(distance))\(etaText)"
    }

    private func meetingPointProgressSummary(
        _ progress: [MeetingPointMemberProgress]
    ) -> String {
        let unavailable = progress.filter { $0.distanceMeters == nil }.count
        let enRoute = progress.count
            - progress.filter(\.hasArrived).count
            - unavailable
        return "\(enRoute) 人途中 · \(unavailable) 人未共享位置"
    }

    private func durationText(_ duration: TimeInterval) -> String {
        if duration <= 60 {
            return "1 分钟"
        }
        let minutes = Int(ceil(duration / 60))
        if minutes < 60 {
            return "\(minutes) 分钟"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0
            ? "\(hours) 小时"
            : "\(hours) 小时 \(remainingMinutes) 分钟"
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
