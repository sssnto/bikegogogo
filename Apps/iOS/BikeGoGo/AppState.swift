import BikeGoGoCore
import Combine
import CoreLocation
import Foundation

enum VoiceCallPhase: Equatable {
    case idle
    case preparing
    case calling
    case connecting
    case syncingAudio
    case connected
    case reconnecting
    case waitingForParticipants

    var title: String {
        switch self {
        case .idle: "未连接语音"
        case .preparing: "正在准备呼叫"
        case .calling: "正在呼叫"
        case .connecting: "正在建立连接"
        case .syncingAudio: "正在同步音频"
        case .connected: "语音已连接"
        case .reconnecting: "网络波动，正在重连"
        case .waitingForParticipants: "等待对方加入"
        }
    }

    var systemImage: String {
        switch self {
        case .idle: "phone"
        case .preparing, .calling: "phone.fill"
        case .connecting, .reconnecting: "arrow.clockwise"
        case .syncingAudio: "waveform"
        case .connected: "checkmark.circle.fill"
        case .waitingForParticipants: "person.2.fill"
        }
    }

    var showsProgress: Bool {
        switch self {
        case .preparing, .calling, .connecting, .syncingAudio, .reconnecting:
            true
        case .idle, .connected, .waitingForParticipants:
            false
        }
    }
}

struct ActiveVoiceCallContext: Equatable {
    var targetID: String
    var targetName: String
    var isGroupCall: Bool
    var isOutgoing: Bool
}

@MainActor
final class AppState: ObservableObject {
    @Published var currentRide = RideSession(
        title: "准备开始骑行",
        state: .idle,
        source: .iPhone,
        points: []
    )
    @Published var recentRides: [RideSession] = []
    @Published var group = SampleData.group
    @Published var voiceRoom = SampleData.voiceRoom
    @Published private(set) var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var currentSpeedMetersPerSecond = 0.0
    @Published private(set) var locationAccuracyMeters: Double?
    @Published private(set) var currentReliableLocation: RidePoint?
    @Published private(set) var currentWeather: RideWeatherSnapshot?
    @Published private(set) var isRefreshingWeather = false
    @Published private(set) var weatherMessage: String?
    @Published private(set) var weatherAttributionURL: URL?
    @Published private(set) var isWaitingForAccurateLocation = false
    @Published private(set) var isAutomaticallyPaused = false
    @Published private(set) var watchHeartRate = 0.0
    @Published var rideAlertMessage: String?
    @Published private(set) var isSyncingRides = false
    @Published private(set) var rideSyncMessage: String?
    @Published private(set) var lastRideSyncAt: Date?
    @Published private(set) var isImportingHealthKit = false
    @Published private(set) var healthKitImportMessage: String?
    @Published private(set) var lastHealthKitImportAt: Date?
    @Published private(set) var incomingVoiceInvitation: VoiceInvitation?
    @Published private(set) var outgoingVoiceInvitation: VoiceInvitation?
    @Published private(set) var activeVoiceCallContext: ActiveVoiceCallContext?
    @Published private(set) var isHandlingVoiceInvitation = false
    @Published var voiceCallMessage: String?
    @Published private(set) var isSharingRideLocation = false
    @Published private(set) var locationSharingGroupID: String?
    @Published private(set) var teammateLocations: [GroupLiveLocation] = []
    @Published private(set) var locationSharingMessage: String?
    @Published private(set) var incomingTeamSOS: TeamSOSPushEvent?
    @Published private(set) var isSendingTeamSOS = false
    @Published private(set) var teamRideMemberStatuses: [TeamRideMemberStatus] = []
    @Published private(set) var teamSafetyAlertsEnabled = true
    @Published private(set) var teamMeetingPoint: GroupMeetingPoint?
    @Published private(set) var isUpdatingTeamMeetingPoint = false
    @Published private(set) var meetingPointArrivalEvaluation:
        MeetingPointArrivalEvaluation?
    @Published private(set) var referenceRideID: UUID?
    @Published private(set) var routeDeviationEvaluation: RouteDeviationEvaluation?

    private let rideStore = LocalRideStore()
    private let rideCloudClient = RideCloudClient()
    let rideRecorder = LocationRideRecorder()
    let voiceClient = VoiceRoomClient()
    let accountClient = AccountClient()
    let watchBridge = WatchSessionBridge()
    private let watchWorkoutLauncher = WatchWorkoutLauncher()
    private let healthKitRideImporter = HealthKitRideImporter()
    private let rideWeatherService = RideWeatherService()
    private let voiceTokenService = VoiceTokenService()
    private let groupLiveLocationService = GroupLiveLocationService()
    private let localUserID: String
    private let localDisplayName: String
    private var cancellables: Set<AnyCancellable> = []
    private var pendingStartAfterAuthorization = false
    private var activeElapsedSeconds: TimeInterval = 0
    private var activeSegmentStartedAt: Date?
    private var latestWatchCadenceRPM = 0.0
    private var latestWatchCyclingPowerWatts = 0.0
    private var healthKitRefreshTask: Task<Void, Never>?
    private var autoPauseEvaluationTask: Task<Void, Never>?
    private var autoPauseMonitor = RideAutoPauseMonitor()
    private var recorderNeedsRestart = false
    private var activeVoiceInvitationID: String?
    private var locationSharingRefreshTask: Task<Void, Never>?
    private var liveLocationUploadPolicy = LiveLocationUploadPolicy()
    private var isPublishingRideLocation = false
    private var teamSafetyMonitor = TeamRideSafetyMonitor()
    private var meetingPointArrivalMonitor = MeetingPointArrivalMonitor()
    private var routeDeviationMonitor = RouteDeviationMonitor()
    private static let teamSafetyAlertsDefaultsKey = "bikegogo.teamSafetyAlertsEnabled"

    init() {
        if UserDefaults.standard.object(
            forKey: Self.teamSafetyAlertsDefaultsKey
        ) != nil {
            teamSafetyAlertsEnabled = UserDefaults.standard.bool(
                forKey: Self.teamSafetyAlertsDefaultsKey
            )
        }
        let identityKey = "bikegogo.localVoiceIdentity"
        if let storedIdentity = UserDefaults.standard.string(forKey: identityKey) {
            localUserID = storedIdentity
        } else {
            let newIdentity = UUID().uuidString.lowercased()
            UserDefaults.standard.set(newIdentity, forKey: identityKey)
            localUserID = newIdentity
        }
        localDisplayName = "骑友-\(localUserID.prefix(4).uppercased())"
        accountClient.beforeSignOut = { [weak self] in
            guard let self, let accessToken = self.accountClient.accessToken else { return }
            await PushNotificationManager.shared.unregisterCurrentToken(accessToken: accessToken)
            await self.stopRideLocationSharing()
        }

        accountClient.$accessToken
            .removeDuplicates()
            .sink { accessToken in
                Task { @MainActor in
                    await PushNotificationManager.shared.configure(
                        accessToken: accessToken
                    )
                }
            }
            .store(in: &cancellables)

        rideRecorder.$authorizationStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self else { return }
                self.locationAuthorizationStatus = status
                if self.pendingStartAfterAuthorization,
                   status == .authorizedAlways || status == .authorizedWhenInUse {
                    self.pendingStartAfterAuthorization = false
                    self.beginNewRide()
                }
            }
            .store(in: &cancellables)

        rideRecorder.$currentSpeedMetersPerSecond
            .receive(on: RunLoop.main)
            .assign(to: &$currentSpeedMetersPerSecond)

        rideRecorder.$locationAccuracyMeters
            .receive(on: RunLoop.main)
            .assign(to: &$locationAccuracyMeters)

        rideRecorder.$isWaitingForAccurateLocation
            .receive(on: RunLoop.main)
            .assign(to: &$isWaitingForAccurateLocation)

        rideRecorder.$lastErrorMessage
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] message in
                self?.rideAlertMessage = message
            }
            .store(in: &cancellables)

        voiceClient.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        accountClient.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        PushNotificationManager.shared.onVoiceEvent = { [weak self] event in
            guard let self else { return }
            Task { @MainActor in
                await self.handleVoicePushEvent(event)
            }
        }
        PushNotificationManager.shared.deliverPendingVoiceEvents()
        PushNotificationManager.shared.onTeamSOSEvent = { [weak self] event in
            self?.incomingTeamSOS = event
        }
        PushNotificationManager.shared.deliverPendingTeamSOSEvents()
    }

    func bootstrap() async {
        rideRecorder.onPointsChanged = { [weak self] points in
            Task { @MainActor in
                guard let self else { return }
                var enrichedPoints = points
                if !enrichedPoints.isEmpty {
                    let lastIndex = enrichedPoints.count - 1
                    if self.watchHeartRate > 0 {
                        enrichedPoints[lastIndex].heartRateBeatsPerMinute = Int(
                            self.watchHeartRate.rounded()
                        )
                    }
                    if self.latestWatchCadenceRPM > 0 {
                        enrichedPoints[lastIndex].cadenceRPM = Int(
                            self.latestWatchCadenceRPM.rounded()
                        )
                    }
                    if self.latestWatchCyclingPowerWatts > 0 {
                        enrichedPoints[lastIndex].cyclingPowerWatts =
                            self.latestWatchCyclingPowerWatts
                    }
                }

                let previousMetrics = self.currentRide.metrics
                var metrics = RideStatisticsCalculator.metrics(for: enrichedPoints)
                metrics.elapsedDurationSeconds = self.rideElapsedDuration()
                metrics.activeEnergyKilocalories = previousMetrics.activeEnergyKilocalories
                metrics.totalEnergyKilocalories = previousMetrics.totalEnergyKilocalories
                if metrics.averageHeartRate == nil {
                    metrics.averageHeartRate = previousMetrics.averageHeartRate
                    metrics.maxHeartRate = previousMetrics.maxHeartRate
                }
                if metrics.averageCadenceRPM == nil {
                    metrics.averageCadenceRPM = previousMetrics.averageCadenceRPM
                    metrics.maxCadenceRPM = previousMetrics.maxCadenceRPM
                }
                if metrics.averageCyclingPowerWatts == nil {
                    metrics.averageCyclingPowerWatts = previousMetrics.averageCyclingPowerWatts
                    metrics.maxCyclingPowerWatts = previousMetrics.maxCyclingPowerWatts
                }
                self.currentRide.points = enrichedPoints
                self.currentRide.metrics = metrics
                await self.persistActiveRide()
                await self.evaluateRouteDeviation(enrichedPoints.last)
            }
        }
        rideRecorder.onReliableLocationChanged = { [weak self] point in
            Task { @MainActor in
                guard let self else { return }
                self.currentReliableLocation = point
                if self.currentRide.weather == nil {
                    await self.refreshWeather(at: point)
                }
                await self.publishRideLocationIfNeeded(point)
                await self.evaluateMeetingPointArrival(point)
            }
        }
        rideRecorder.onCurrentLocationChanged = { [weak self] point in
            Task { @MainActor in
                guard let self else { return }
                self.currentReliableLocation = point
                await self.refreshWeather(at: point)
            }
        }
        rideRecorder.onMotionChanged = {
            [weak self] speed, horizontalAccuracy, speedAccuracy, timestamp in
            Task { @MainActor in
                self?.handleRideMotion(
                    speedMetersPerSecond: speed,
                    horizontalAccuracyMeters: horizontalAccuracy,
                    speedAccuracyMetersPerSecond: speedAccuracy,
                    at: timestamp
                )
            }
        }

        watchBridge.onRideStateReceived = { [weak self] state in
            self?.handleWatchRideState(state)
        }
        watchBridge.onMuteStateReceived = { [weak self] muted in
            guard let self, self.voiceClient.isConnected, self.voiceClient.isMuted != muted else { return }
            Task {
                await self.voiceClient.setMuted(muted)
            }
        }
        watchBridge.onWorkoutMetricsReceived = {
            [weak self] elapsed, distance, heartRate, speed, activeEnergy, cadence, power in
            self?.handleWatchMetrics(
                elapsed: elapsed,
                distance: distance,
                heartRate: heartRate,
                speed: speed,
                activeEnergy: activeEnergy,
                cadence: cadence,
                power: power
            )
        }

        await accountClient.bootstrap(
            defaultDisplayName: localDisplayName,
            presentsErrors: false
        )
        await PushNotificationManager.shared.requestAuthorization()
        await refreshIncomingVoiceInvitations()
        await loadStoredRides()
        await syncRides()
        watchBridge.activate()
    }

    func requestRidePermissions() {
        rideRecorder.requestAuthorization()
        rideRecorder.requestCurrentLocation()
    }

    func refreshRideWeather() {
        weatherMessage = nil
        rideRecorder.requestCurrentLocation()
    }

    func startRide() {
        switch locationAuthorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            beginNewRide()
        case .notDetermined:
            pendingStartAfterAuthorization = true
            rideRecorder.requestAuthorization()
        case .denied:
            rideAlertMessage = "定位权限已关闭，请到“设置 > 隐私与安全性 > 定位服务 > BikeGoGo”中允许定位。"
        case .restricted:
            rideAlertMessage = "此设备限制了定位权限，暂时无法开始记录骑行。"
        @unknown default:
            rideAlertMessage = "无法确认定位权限，请稍后重试。"
        }
    }

    private func beginNewRide() {
        let now = Date()
        activeElapsedSeconds = 0
        activeSegmentStartedAt = now
        watchHeartRate = 0
        latestWatchCadenceRPM = 0
        latestWatchCyclingPowerWatts = 0
        isAutomaticallyPaused = false
        autoPauseMonitor.reset()
        autoPauseEvaluationTask?.cancel()
        recorderNeedsRestart = false
        currentReliableLocation = nil
        currentRide = RideSession(
            title: "本次骑行",
            state: .recording,
            source: .iPhone,
            startedAt: now,
            weather: usableWeatherSnapshot(at: now)
        )
        rideRecorder.start()
        rideRecorder.requestCurrentLocation()
        watchBridge.sendRideState(.recording)
        Task {
            do {
                try await healthKitRideImporter.requestAuthorization()
            } catch {
                rideAlertMessage = "苹果健康数据授权失败，本次仍会保留手机骑行记录。"
            }
            do {
                try await watchWorkoutLauncher.startOutdoorCycling()
            } catch {
                print("Starting Apple Watch workout failed: \(error.localizedDescription)")
            }
            await persistActiveRide()
        }
    }

    func pauseRide(automatically: Bool = false) {
        guard currentRide.state == .recording else { return }
        activeElapsedSeconds = rideElapsedDuration()
        activeSegmentStartedAt = nil
        currentRide.state = .paused
        isAutomaticallyPaused = automatically
        autoPauseMonitor.reset()
        autoPauseEvaluationTask?.cancel()
        currentRide.metrics.elapsedDurationSeconds = activeElapsedSeconds
        rideRecorder.pause(keepingMotionUpdates: automatically)
        watchBridge.sendRideState(.paused)
        Task {
            await persistActiveRide()
        }
    }

    func resumeRide() {
        guard currentRide.state == .paused else { return }
        activeSegmentStartedAt = Date()
        currentRide.state = .recording
        isAutomaticallyPaused = false
        autoPauseMonitor.reset()
        autoPauseEvaluationTask?.cancel()
        if recorderNeedsRestart {
            rideRecorder.start(keepingExistingPoints: true)
            recorderNeedsRestart = false
        } else {
            rideRecorder.resume()
        }
        watchBridge.sendRideState(.recording)
        Task {
            await persistActiveRide()
        }
    }

    func finishRide() {
        let finishedRideStartedAt = currentRide.startedAt
        activeElapsedSeconds = rideElapsedDuration()
        activeSegmentStartedAt = nil
        currentRide.state = .finished
        currentRide.endedAt = Date()
        currentRide.points = rideRecorder.points
        currentRide.metrics = RideStatisticsCalculator.metrics(for: currentRide.points)
        currentRide.metrics.elapsedDurationSeconds = activeElapsedSeconds
        rideRecorder.stop()
        isAutomaticallyPaused = false
        autoPauseMonitor.reset()
        autoPauseEvaluationTask?.cancel()
        currentReliableLocation = nil

        if !currentRide.points.isEmpty {
            recentRides.insert(currentRide, at: 0)
            Task {
                await saveRecentRides()
                await syncRides()
            }
        }
        Task {
            await stopRideLocationSharing()
            try? await rideStore.clearActiveRide()
        }
        watchBridge.sendRideState(.finished)
        scheduleHealthKitRefresh(forRideStartedAt: finishedRideStartedAt)
        clearReferenceRoute()
        rideRecorder.requestCurrentLocation()
    }

    private func refreshWeather(at point: RidePoint) async {
        let location = CLLocation(
            latitude: point.latitude,
            longitude: point.longitude
        )
        if let currentWeather,
           Date().timeIntervalSince(currentWeather.capturedAt) < 20 * 60 {
            let weatherLocation = CLLocation(
                latitude: currentWeather.latitude,
                longitude: currentWeather.longitude
            )
            if location.distance(from: weatherLocation) < 10_000 {
                attachWeatherToActiveRideIfNeeded(currentWeather)
                return
            }
        }

        guard !isRefreshingWeather else { return }
        isRefreshingWeather = true
        defer { isRefreshingWeather = false }
        do {
            let reading = try await rideWeatherService.weather(at: point)
            currentWeather = reading.snapshot
            weatherAttributionURL = reading.legalPageURL
            weatherMessage = nil
            attachWeatherToActiveRideIfNeeded(reading.snapshot)
        } catch {
            weatherMessage = "天气暂时无法更新"
            print("Refreshing WeatherKit weather failed: \(error.localizedDescription)")
        }
    }

    private func attachWeatherToActiveRideIfNeeded(
        _ weather: RideWeatherSnapshot
    ) {
        guard currentRide.state == .recording || currentRide.state == .paused,
              currentRide.weather == nil else { return }
        currentRide.weather = weather
        Task {
            await persistActiveRide()
        }
    }

    private func usableWeatherSnapshot(at date: Date) -> RideWeatherSnapshot? {
        guard let currentWeather,
              abs(date.timeIntervalSince(currentWeather.capturedAt)) <= 60 * 60 else {
            return nil
        }
        return currentWeather
    }

    func discardCurrentRide() {
        rideRecorder.stop()
        isAutomaticallyPaused = false
        autoPauseMonitor.reset()
        autoPauseEvaluationTask?.cancel()
        currentReliableLocation = nil
        currentRide = RideSession(
            title: "准备开始骑行",
            state: .idle,
            source: .iPhone,
            points: []
        )
        activeElapsedSeconds = 0
        activeSegmentStartedAt = nil
        recorderNeedsRestart = false
        clearReferenceRoute()
        Task {
            await stopRideLocationSharing()
            try? await rideStore.clearActiveRide()
        }
    }

    func rideElapsedDuration(at date: Date = Date()) -> TimeInterval {
        guard currentRide.state == .recording, let activeSegmentStartedAt else {
            return activeElapsedSeconds
        }
        return activeElapsedSeconds + max(date.timeIntervalSince(activeSegmentStartedAt), 0)
    }

    func exportGPX(for ride: RideSession) async -> URL? {
        do {
            return try await rideStore.exportGPX(for: ride)
        } catch {
            print("GPX export failed: \(error.localizedDescription)")
            return nil
        }
    }

    var canDeleteAccount: Bool {
        currentRide.state != .recording && currentRide.state != .paused
    }

    func deleteAccountAndLocalData(
        appleAuthorizationCode: String? = nil,
        appleRawNonce: String? = nil
    ) async -> Bool {
        guard canDeleteAccount else {
            accountClient.errorMessage = "请先结束或放弃当前骑行，再永久删除账户。"
            return false
        }
        guard await accountClient.deleteAccount(
            appleAuthorizationCode: appleAuthorizationCode,
            appleRawNonce: appleRawNonce
        ) else { return false }

        await voiceClient.leave()
        await stopRideLocationSharing()
        incomingVoiceInvitation = nil
        outgoingVoiceInvitation = nil
        activeVoiceCallContext = nil
        activeVoiceInvitationID = nil
        voiceRoom.isJoined = false
        recentRides = []
        rideSyncMessage = nil
        lastRideSyncAt = nil
        currentRide = RideSession(
            title: "准备开始骑行",
            state: .idle,
            source: .iPhone,
            points: []
        )
        do {
            try await rideStore.deleteAllData()
        } catch {
            print("Deleting local account data failed: \(error.localizedDescription)")
        }

        await accountClient.bootstrap(defaultDisplayName: localDisplayName)
        accountClient.statusMessage = "原账户及其云端数据已永久删除"
        return true
    }

    func joinVoiceRoom(roomID: String) async {
        await voiceClient.join(
            groupID: roomID,
            accessToken: accountClient.accessToken
        )
        voiceRoom.isJoined = voiceClient.isConnected
    }

    var voiceCallPhase: VoiceCallPhase {
        if voiceClient.status == .reconnecting {
            return .reconnecting
        }
        if outgoingVoiceInvitation != nil,
           voiceClient.remoteParticipantCount == 0,
           !voiceClient.hasHadRemoteParticipant {
            return .calling
        }
        if voiceClient.status == .connecting {
            return .connecting
        }
        if voiceClient.status == .connected {
            guard voiceClient.remoteParticipantCount > 0 else {
                return .waitingForParticipants
            }
            guard voiceClient.isLocalAudioReady,
                  voiceClient.remoteAudioReadyCount > 0 else {
                return .syncingAudio
            }
            return .connected
        }
        if isHandlingVoiceInvitation || outgoingVoiceInvitation != nil {
            return .preparing
        }
        return .idle
    }

    var hasActiveVoiceCall: Bool {
        voiceCallPhase != .idle
    }

    var voiceCallStatusDetail: String {
        let targetName = activeVoiceCallContext?.targetName ?? "语音房间"
        switch voiceCallPhase {
        case .idle:
            return "选择好友或小队后发起语音"
        case .preparing:
            return "正在创建与\(targetName)的呼叫"
        case .calling:
            return "已通知\(targetName)，等待接听"
        case .connecting:
            return "正在连接\(targetName)的语音房间"
        case .syncingAudio:
            return "已找到对方，正在建立双向音频"
        case .connected:
            return "\(targetName) · \(voiceClient.remoteParticipantCount + 1) 人在线"
        case .reconnecting:
            return "通话暂未断开，正在恢复网络"
        case .waitingForParticipants:
            return voiceClient.hasHadRemoteParticipant
                ? "\(targetName)已离开，等待重新加入"
                : "已进入\(targetName)，等待其他成员"
        }
    }

    func startVoiceCall(targetID: String) async {
        guard let accessToken = accountClient.accessToken else {
            voiceCallMessage = "请先建立 BikeGoGo 账户。"
            return
        }
        guard !isHandlingVoiceInvitation, !voiceClient.isConnected else { return }
        isHandlingVoiceInvitation = true
        voiceCallMessage = nil
        defer { isHandlingVoiceInvitation = false }

        do {
            let invitation = try await voiceTokenService.createInvitation(
                targetID: targetID,
                accessToken: accessToken
            )
            outgoingVoiceInvitation = invitation
            activeVoiceCallContext = ActiveVoiceCallContext(
                targetID: invitation.targetId,
                targetName: invitation.targetName,
                isGroupCall: invitation.isGroupCall,
                isOutgoing: true
            )
            await joinVoiceRoom(roomID: targetID)
            if !voiceClient.isConnected {
                await cancelOutgoingVoiceInvitation()
                activeVoiceCallContext = nil
            }
        } catch {
            activeVoiceCallContext = nil
            voiceCallMessage = "发起语音失败：\(error.localizedDescription)"
        }
    }

    func refreshIncomingVoiceInvitations() async {
        guard let accessToken = accountClient.accessToken,
              !voiceClient.isConnected else { return }
        do {
            incomingVoiceInvitation = try await voiceTokenService
                .pendingInvitations(accessToken: accessToken)
                .first
        } catch {
            print("Refreshing voice invitations failed: \(error.localizedDescription)")
        }
    }

    func acceptIncomingVoiceInvitation() async {
        guard let invitation = incomingVoiceInvitation,
              let accessToken = accountClient.accessToken,
              !isHandlingVoiceInvitation else { return }
        isHandlingVoiceInvitation = true
        voiceCallMessage = nil
        defer { isHandlingVoiceInvitation = false }

        do {
            _ = try await voiceTokenService.respond(
                invitationID: invitation.id,
                action: "accept",
                accessToken: accessToken
            )
            activeVoiceCallContext = ActiveVoiceCallContext(
                targetID: invitation.targetId,
                targetName: invitation.targetName,
                isGroupCall: invitation.isGroupCall,
                isOutgoing: false
            )
            incomingVoiceInvitation = nil
            activeVoiceInvitationID = invitation.id
            await joinVoiceRoom(roomID: invitation.targetId)
            if !voiceClient.isConnected {
                activeVoiceInvitationID = nil
                activeVoiceCallContext = nil
            }
        } catch {
            activeVoiceCallContext = nil
            voiceCallMessage = "接听失败：\(error.localizedDescription)"
            await refreshIncomingVoiceInvitations()
        }
    }

    func declineIncomingVoiceInvitation() async {
        guard let invitation = incomingVoiceInvitation,
              let accessToken = accountClient.accessToken,
              !isHandlingVoiceInvitation else { return }
        isHandlingVoiceInvitation = true
        defer { isHandlingVoiceInvitation = false }
        do {
            _ = try await voiceTokenService.respond(
                invitationID: invitation.id,
                action: "decline",
                accessToken: accessToken
            )
        } catch {
            print("Declining voice invitation failed: \(error.localizedDescription)")
        }
        incomingVoiceInvitation = nil
    }

    func dismissIncomingVoiceInvitationIfExpired(_ invitationID: String) {
        guard incomingVoiceInvitation?.id == invitationID else { return }
        incomingVoiceInvitation = nil
    }

    func leaveVoiceRoom() async {
        await cancelOutgoingVoiceInvitation()
        await voiceClient.leave()
        activeVoiceInvitationID = nil
        activeVoiceCallContext = nil
        voiceRoom.isJoined = false
    }

    func toggleMute() async {
        await voiceClient.setMuted(!voiceClient.isMuted)
        voiceRoom.isMuted = voiceClient.isMuted
        watchBridge.sendMuteState(voiceClient.isMuted)
    }

    func callActiveRideTeam() async {
        guard let group = activeLocationSharingGroup else {
            rideAlertMessage = "请先选择一个小队并开启位置共享。"
            return
        }
        await startVoiceCall(targetID: group.id)
        if let voiceCallMessage {
            rideAlertMessage = voiceCallMessage
            self.voiceCallMessage = nil
        }
    }

    var activeLocationSharingGroup: AppGroup? {
        guard let locationSharingGroupID else { return nil }
        return accountClient.groups.first { $0.id == locationSharingGroupID }
    }

    var referenceRide: RideSession? {
        guard let referenceRideID else { return nil }
        return recentRides.first { $0.id == referenceRideID }
    }

    func selectReferenceRoute(_ ride: RideSession) {
        guard ride.points.count > 1 else {
            rideAlertMessage = "这条历史骑行没有足够的轨迹点。"
            return
        }
        referenceRideID = ride.id
        routeDeviationMonitor.reset()
        routeDeviationEvaluation = nil
    }

    func clearReferenceRoute() {
        referenceRideID = nil
        routeDeviationMonitor.reset()
        routeDeviationEvaluation = nil
    }

    func sendTeamSOS(groupID: String) async {
        guard currentRide.state == .recording || currentRide.state == .paused else {
            rideAlertMessage = "开始骑行后才能向小队发送紧急求助。"
            return
        }
        guard let group = accountClient.groups.first(where: { $0.id == groupID }),
              let accessToken = accountClient.accessToken else {
            rideAlertMessage = "当前小队或账户状态不可用，请刷新后重试。"
            return
        }
        guard let point = currentReliableLocation,
              abs(Date().timeIntervalSince(point.timestamp)) <= 30,
              let accuracy = point.horizontalAccuracyMeters,
              accuracy <= RideLocationFilter.maximumTrackingHorizontalAccuracyMeters else {
            rideAlertMessage = "正在等待准确的 GPS 位置，请到开阔处稍后重试。"
            return
        }
        guard !isSendingTeamSOS else { return }

        isSendingTeamSOS = true
        defer { isSendingTeamSOS = false }
        if locationSharingGroupID != groupID || !isSharingRideLocation {
            await startRideLocationSharing(groupID: groupID)
        }

        do {
            let recipientCount = try await groupLiveLocationService.sendSOS(
                groupID: groupID,
                point: point,
                accessToken: accessToken
            )
            if recipientCount == 0 {
                rideAlertMessage = "\(group.name) 暂无其他成员，未发送求助通知。"
            } else {
                rideAlertMessage = "紧急求助已发出，并向 \(recipientCount) 位小队成员共享了当前位置。"
            }
        } catch {
            rideAlertMessage = "紧急求助发送失败，请直接拨打电话或联系队友。"
            print("Sending team SOS failed: \(error.localizedDescription)")
        }
    }

    func dismissIncomingTeamSOS() {
        incomingTeamSOS = nil
    }

    func setTeamSafetyAlertsEnabled(_ enabled: Bool) {
        teamSafetyAlertsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.teamSafetyAlertsDefaultsKey)
        teamSafetyMonitor.reset()
        teamRideMemberStatuses = []
    }

    func startRideLocationSharing(groupID: String) async {
        guard currentRide.state == .recording || currentRide.state == .paused else {
            rideAlertMessage = "开始骑行后才能共享本次位置。"
            return
        }
        guard accountClient.groups.contains(where: { $0.id == groupID }),
              accountClient.accessToken != nil else {
            rideAlertMessage = "请先加入一个小队并建立账户。"
            return
        }

        let startsNewSafetySession = locationSharingGroupID != groupID
            || !isSharingRideLocation
        if let previousGroupID = locationSharingGroupID,
           previousGroupID != groupID {
            await stopRideLocationSharing()
        }
        if startsNewSafetySession {
            teamSafetyMonitor.reset()
            teamRideMemberStatuses = []
        }

        locationSharingGroupID = groupID
        isSharingRideLocation = true
        locationSharingMessage = nil
        liveLocationUploadPolicy.reset()
        await publishRideLocationIfNeeded(currentReliableLocation, force: true)
        await refreshTeammateLocations()
        await refreshTeamMeetingPoint()
        startLocationSharingRefreshLoop()
    }

    func stopRideLocationSharing() async {
        locationSharingRefreshTask?.cancel()
        locationSharingRefreshTask = nil
        let groupID = locationSharingGroupID
        let accessToken = accountClient.accessToken
        locationSharingGroupID = nil
        isSharingRideLocation = false
        teammateLocations = []
        locationSharingMessage = nil
        liveLocationUploadPolicy.reset()
        teamSafetyMonitor.reset()
        teamRideMemberStatuses = []
        teamMeetingPoint = nil
        meetingPointArrivalMonitor.reset()
        meetingPointArrivalEvaluation = nil

        guard let groupID, let accessToken else { return }
        do {
            try await groupLiveLocationService.stop(
                groupID: groupID,
                accessToken: accessToken
            )
        } catch {
            print("Stopping ride location sharing failed: \(error.localizedDescription)")
        }
    }

    func setTeamMeetingPoint(groupID: String, title: String) async {
        guard let group = accountClient.groups.first(where: { $0.id == groupID }),
              group.isOwner,
              let accessToken = accountClient.accessToken else {
            rideAlertMessage = "只有小队创建者可以设置集合点。"
            return
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            rideAlertMessage = "请输入集合点名称。"
            return
        }
        guard let point = currentReliableLocation,
              abs(Date().timeIntervalSince(point.timestamp)) <= 30,
              let accuracy = point.horizontalAccuracyMeters,
              accuracy <= RideLocationFilter.maximumTrackingHorizontalAccuracyMeters else {
            rideAlertMessage = "正在等待准确的 GPS 位置，请到开阔处稍后重试。"
            return
        }
        guard !isUpdatingTeamMeetingPoint else { return }

        isUpdatingTeamMeetingPoint = true
        defer { isUpdatingTeamMeetingPoint = false }
        do {
            let meetingPoint = try await groupLiveLocationService.setMeetingPoint(
                groupID: groupID,
                point: point,
                title: String(trimmedTitle.prefix(40)),
                accessToken: accessToken
            )
            teamMeetingPoint = meetingPoint
            meetingPointArrivalMonitor.reset()
            meetingPointArrivalEvaluation = nil
            await evaluateMeetingPointArrival(point)
            rideAlertMessage = "已将当前位置设为「\(meetingPoint.title)」，有效期 6 小时。"
        } catch {
            rideAlertMessage = "集合点设置失败，请检查网络后重试。"
            print("Setting team meeting point failed: \(error.localizedDescription)")
        }
    }

    func clearTeamMeetingPoint(groupID: String) async {
        guard let group = accountClient.groups.first(where: { $0.id == groupID }),
              group.isOwner,
              let accessToken = accountClient.accessToken else {
            rideAlertMessage = "只有小队创建者可以清除集合点。"
            return
        }
        guard !isUpdatingTeamMeetingPoint else { return }

        isUpdatingTeamMeetingPoint = true
        defer { isUpdatingTeamMeetingPoint = false }
        do {
            try await groupLiveLocationService.clearMeetingPoint(
                groupID: groupID,
                accessToken: accessToken
            )
            teamMeetingPoint = nil
            meetingPointArrivalMonitor.reset()
            meetingPointArrivalEvaluation = nil
            rideAlertMessage = "已清除「\(group.name)」集合点。"
        } catch {
            rideAlertMessage = "集合点清除失败，请检查网络后重试。"
            print("Clearing team meeting point failed: \(error.localizedDescription)")
        }
    }

    private func publishRideLocationIfNeeded(
        _ point: RidePoint?,
        force: Bool = false
    ) async {
        guard isSharingRideLocation,
              !isPublishingRideLocation,
              let point,
              let groupID = locationSharingGroupID,
              let accessToken = accountClient.accessToken else { return }
        if let accuracy = point.horizontalAccuracyMeters,
           accuracy > RideLocationFilter.maximumTrackingHorizontalAccuracyMeters {
            return
        }
        let requestedAt = Date()
        guard liveLocationUploadPolicy.shouldUpload(
            point,
            at: requestedAt,
            force: force
        ) else {
            return
        }

        isPublishingRideLocation = true
        defer { isPublishingRideLocation = false }
        do {
            try await groupLiveLocationService.update(
                groupID: groupID,
                point: point,
                accessToken: accessToken
            )
            liveLocationUploadPolicy.markUploaded(point)
            locationSharingMessage = nil
        } catch {
            locationSharingMessage = "位置共享网络暂时中断"
            print("Publishing ride location failed: \(error.localizedDescription)")
        }
    }

    private func refreshTeammateLocations() async {
        guard isSharingRideLocation,
              let groupID = locationSharingGroupID,
              let accessToken = accountClient.accessToken else { return }
        guard accountClient.groups.contains(where: { $0.id == groupID }) else {
            await stopRideLocationSharing()
            return
        }

        do {
            let locations = try await groupLiveLocationService.locations(
                groupID: groupID,
                accessToken: accessToken
            )
            teammateLocations = locations.filter {
                $0.user.id != accountClient.currentUser?.id
            }
            await updateTeamSafetyStatus(with: teammateLocations)
            locationSharingMessage = nil
        } catch {
            locationSharingMessage = "队友位置暂时无法刷新"
            print("Refreshing teammate locations failed: \(error.localizedDescription)")
        }
    }

    private func refreshTeamMeetingPoint() async {
        guard isSharingRideLocation,
              let groupID = locationSharingGroupID,
              let accessToken = accountClient.accessToken else { return }
        do {
            let meetingPoint = try await groupLiveLocationService.meetingPoint(
                groupID: groupID,
                accessToken: accessToken
            )
            if meetingPoint?.updatedAt != teamMeetingPoint?.updatedAt {
                meetingPointArrivalMonitor.reset()
                meetingPointArrivalEvaluation = nil
            }
            teamMeetingPoint = meetingPoint
            await evaluateMeetingPointArrival(currentReliableLocation)
        } catch {
            print("Refreshing team meeting point failed: \(error.localizedDescription)")
        }
    }

    private func updateTeamSafetyStatus(
        with locations: [GroupLiveLocation]
    ) async {
        guard let riderLocation = currentReliableLocation else {
            teamRideMemberStatuses = []
            return
        }
        let samples = locations.compactMap { location -> TeamRideLocationSample? in
            guard let updatedAt = serverDate(from: location.updatedAt) else {
                return nil
            }
            return TeamRideLocationSample(
                userID: location.user.id,
                displayName: location.user.displayName,
                latitude: location.latitude,
                longitude: location.longitude,
                updatedAt: updatedAt
            )
        }
        let evaluation = teamSafetyMonitor.evaluate(
            riderLocation: riderLocation,
            samples: samples
        )
        teamRideMemberStatuses = evaluation.statuses
        guard teamSafetyAlertsEnabled, !evaluation.newAlerts.isEmpty else {
            return
        }

        let alertBody: String
        if evaluation.newAlerts.count == 1,
           let alert = evaluation.newAlerts.first {
            switch alert.kind {
            case .separated:
                let distance = Int((alert.distanceMeters ?? 0).rounded())
                alertBody = "\(alert.displayName) 距离你约 \(distance) 米，请确认是否掉队。"
            case .signalLost:
                alertBody = "\(alert.displayName) 的位置已超过 60 秒未更新，请尝试联系。"
            }
        } else {
            alertBody = "\(evaluation.newAlerts.count) 位队友出现掉队或位置中断，请查看小队状态。"
        }
        await PushNotificationManager.shared.presentTeamSafetyNotification(
            identifier: "team-safety-\(UUID().uuidString)",
            title: "小队骑行提醒",
            body: alertBody
        )
    }

    private func evaluateRouteDeviation(_ riderLocation: RidePoint?) async {
        guard let riderLocation, let referenceRide else {
            routeDeviationEvaluation = nil
            return
        }
        let evaluation = routeDeviationMonitor.evaluate(
            riderLocation: riderLocation,
            referenceRoute: referenceRide.points
        )
        routeDeviationEvaluation = evaluation
        guard evaluation?.shouldAlert == true else { return }

        let distance = Int((evaluation?.distanceMeters ?? 0).rounded())
        await PushNotificationManager.shared.presentTeamSafetyNotification(
            identifier: "route-deviation-\(UUID().uuidString)",
            title: "路线偏航提醒",
            body: "你已持续偏离参考路线约 \(distance) 米，请查看地图确认方向。"
        )
    }

    private func evaluateMeetingPointArrival(
        _ riderLocation: RidePoint?
    ) async {
        guard let riderLocation, let teamMeetingPoint else {
            meetingPointArrivalEvaluation = nil
            return
        }
        let evaluation = meetingPointArrivalMonitor.evaluate(
            riderLocation: riderLocation,
            meetingPointLatitude: teamMeetingPoint.latitude,
            meetingPointLongitude: teamMeetingPoint.longitude
        )
        meetingPointArrivalEvaluation = evaluation
        guard evaluation.shouldAlert else { return }

        await PushNotificationManager.shared.presentTeamSafetyNotification(
            identifier: "meeting-point-arrival-\(UUID().uuidString)",
            title: "已到达集合点",
            body: "你已进入「\(teamMeetingPoint.title)」100 米范围。"
        )
    }

    private func serverDate(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    private func startLocationSharingRefreshLoop() {
        locationSharingRefreshTask?.cancel()
        locationSharingRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let refreshIntervalSeconds: UInt64 =
                    self.currentRide.state == .recording
                    && self.currentSpeedMetersPerSecond >= 1.5
                    ? 12
                    : 25
                try? await Task.sleep(
                    nanoseconds: refreshIntervalSeconds * 1_000_000_000
                )
                guard !Task.isCancelled else { return }
                await self.publishRideLocationIfNeeded(
                    self.currentReliableLocation
                )
                await self.refreshTeammateLocations()
                await self.refreshTeamMeetingPoint()
            }
        }
    }

    private func cancelOutgoingVoiceInvitation() async {
        guard let invitation = outgoingVoiceInvitation else { return }
        outgoingVoiceInvitation = nil
        guard let accessToken = accountClient.accessToken else { return }
        try? await voiceTokenService.cancelInvitation(
            invitationID: invitation.id,
            accessToken: accessToken
        )
    }

    private func handleVoicePushEvent(_ event: VoicePushEvent) async {
        switch event {
        case .invitation:
            await refreshIncomingVoiceInvitations()
        case let .cancelled(invitationID):
            if incomingVoiceInvitation?.id == invitationID {
                incomingVoiceInvitation = nil
            }
            if activeVoiceInvitationID == invitationID {
                activeVoiceInvitationID = nil
                activeVoiceCallContext = nil
                await voiceClient.leave()
                voiceRoom.isJoined = false
                voiceCallMessage = "发起方已结束本次语音。"
            }
        }
    }

    func syncRides() async {
        guard let accessToken = accountClient.accessToken, !isSyncingRides else { return }
        isSyncingRides = true
        rideSyncMessage = nil
        defer { isSyncingRides = false }

        do {
            recentRides = try await rideCloudClient.synchronize(
                localRides: recentRides,
                accessToken: accessToken
            )
            try await rideStore.saveRides(recentRides)
            lastRideSyncAt = Date()
        } catch {
            rideSyncMessage = "云同步暂时不可用，本地骑行记录不受影响。"
            print("Ride cloud sync failed: \(error.localizedDescription)")
        }
    }

    func refreshRideHistory() async {
        await importHealthKitRides()
        await syncRides()
    }

    func importHealthKitRides(
        since startDate: Date? = nil,
        presentsErrors: Bool = true
    ) async {
        guard !isImportingHealthKit else { return }
        isImportingHealthKit = true
        healthKitImportMessage = nil
        defer { isImportingHealthKit = false }

        do {
            try await healthKitRideImporter.requestAuthorization()
            let importResult: HealthKitRideImporter.ImportResult
            if let startDate {
                importResult = try await healthKitRideImporter.importOutdoorCyclingRides(
                    since: startDate
                )
            } else {
                importResult = try await healthKitRideImporter.importOutdoorCyclingRides()
            }
            let imported = importResult.rides
            recentRides = RideHistoryMerger.merging(
                existing: recentRides,
                imported: imported
            )
            try await rideStore.saveRides(recentRides)
            lastHealthKitImportAt = Date()
            healthKitImportMessage = importResult.discoveredWorkoutCount == 0
                ? "Apple 健康没有返回户外单车训练。请在健康权限中允许 BikeGoGo 读取体能训练、心率和路线。"
                : "Apple 健康读取到 \(importResult.discoveredWorkoutCount) 条户外单车训练，已全部更新。"
        } catch {
            if presentsErrors {
                healthKitImportMessage = "无法读取苹果健身数据，请检查健康权限后重试。"
            }
            print("Importing HealthKit rides failed: \(error.localizedDescription)")
        }
    }

    func deleteRide(_ ride: RideSession) async {
        do {
            if let accessToken = accountClient.accessToken {
                try await rideCloudClient.delete(rideID: ride.id, accessToken: accessToken)
            }
            recentRides.removeAll { $0.id == ride.id }
            try await rideStore.saveRides(recentRides)
            rideSyncMessage = nil
        } catch {
            rideSyncMessage = "删除失败，请检查网络后重试。"
            print("Deleting ride failed: \(error.localizedDescription)")
        }
    }

    private func loadStoredRides() async {
        do {
            let storedRides = try await rideStore.loadRides()
            if !storedRides.isEmpty {
                recentRides = storedRides
            }

            if var activeRide = try await rideStore.loadActiveRide(),
               activeRide.state == .recording || activeRide.state == .paused {
                activeRide.state = .paused
                currentRide = activeRide
                rideRecorder.restore(points: activeRide.points)
                activeElapsedSeconds = max(
                    activeRide.metrics.elapsedDurationSeconds,
                    RideStatisticsCalculator.metrics(for: activeRide.points).elapsedDurationSeconds
                )
                recorderNeedsRestart = true
                isAutomaticallyPaused = false
                autoPauseMonitor.reset()
                rideAlertMessage = "发现一条未结束的骑行记录，已为你暂停。可以继续骑行或结束保存。"
            }
        } catch {
            print("Loading rides failed: \(error.localizedDescription)")
        }
    }

    private func saveRecentRides() async {
        do {
            try await rideStore.saveRides(recentRides)
        } catch {
            print("Saving rides failed: \(error.localizedDescription)")
        }
    }

    private func persistActiveRide() async {
        guard currentRide.state == .recording || currentRide.state == .paused else { return }
        do {
            try await rideStore.saveActiveRide(currentRide)
        } catch {
            print("Saving active ride failed: \(error.localizedDescription)")
        }
    }

    private func handleRideMotion(
        speedMetersPerSecond: Double,
        horizontalAccuracyMeters: Double,
        speedAccuracyMetersPerSecond: Double?,
        at date: Date
    ) {
        guard currentRide.state == .recording
                || currentRide.state == .paused && isAutomaticallyPaused else {
            return
        }

        let action = autoPauseMonitor.observe(
            speedMetersPerSecond: speedMetersPerSecond,
            horizontalAccuracyMeters: horizontalAccuracyMeters,
            speedAccuracyMetersPerSecond: speedAccuracyMetersPerSecond,
            at: date,
            isAutomaticallyPaused: isAutomaticallyPaused
        )
        switch action {
        case .pause where currentRide.state == .recording:
            pauseRide(automatically: true)
        case .resume where currentRide.state == .paused && isAutomaticallyPaused:
            resumeRide()
        case .none, .pause, .resume:
            scheduleAutoPauseEvaluationIfNeeded()
        }
    }

    private func scheduleAutoPauseEvaluationIfNeeded() {
        autoPauseEvaluationTask?.cancel()
        guard currentRide.state == .recording,
              let deadline = autoPauseMonitor.pauseDeadline else {
            return
        }

        let delay = max(deadline.timeIntervalSinceNow, 0)
        autoPauseEvaluationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self, self.currentRide.state == .recording else { return }
            if self.autoPauseMonitor.evaluate(
                at: Date(),
                isAutomaticallyPaused: false
            ) == .pause {
                self.pauseRide(automatically: true)
            }
        }
    }

    private func scheduleHealthKitRefresh(forRideStartedAt startDate: Date) {
        healthKitRefreshTask?.cancel()
        healthKitRefreshTask = Task { [weak self] in
            guard let self else { return }
            let importStartDate = startDate.addingTimeInterval(-10 * 60)
            for delaySeconds in [8, 35] {
                try? await Task.sleep(for: .seconds(delaySeconds))
                guard !Task.isCancelled else { return }
                await self.importHealthKitRides(
                    since: importStartDate,
                    presentsErrors: false
                )
            }
            await self.syncRides()
        }
    }

    private func handleWatchRideState(_ state: RideState) {
        switch state {
        case .recording:
            if currentRide.state == .paused {
                resumeRide()
            } else if currentRide.state == .idle || currentRide.state == .finished {
                startRide()
            }
        case .paused where currentRide.state == .recording:
            pauseRide()
        case .finished where currentRide.state == .recording || currentRide.state == .paused:
            finishRide()
        case .idle, .paused, .finished:
            break
        }
    }

    private func handleWatchMetrics(
        elapsed: TimeInterval,
        distance: Double,
        heartRate: Double,
        speed: Double,
        activeEnergy: Double,
        cadence: Double,
        power: Double
    ) {
        guard currentRide.state == .recording || currentRide.state == .paused else { return }

        watchHeartRate = heartRate
        latestWatchCadenceRPM = cadence
        latestWatchCyclingPowerWatts = power
        if !currentRide.points.isEmpty {
            let lastIndex = currentRide.points.count - 1
            if heartRate > 0 {
                currentRide.points[lastIndex].heartRateBeatsPerMinute = Int(heartRate.rounded())
            }
            if cadence > 0 {
                currentRide.points[lastIndex].cadenceRPM = Int(cadence.rounded())
            }
            if power > 0 {
                currentRide.points[lastIndex].cyclingPowerWatts = power
            }
        }

        var metrics = RideStatisticsCalculator.metrics(for: currentRide.points)
        metrics.elapsedDurationSeconds = max(rideElapsedDuration(), elapsed)
        metrics.distanceMeters = max(metrics.distanceMeters, distance)
        metrics.maxSpeedMetersPerSecond = max(metrics.maxSpeedMetersPerSecond, speed)
        if metrics.movingDurationSeconds == 0, elapsed > 0 {
            metrics.averageSpeedMetersPerSecond = distance / elapsed
        }
        if activeEnergy > 0 {
            metrics.activeEnergyKilocalories = activeEnergy
        }
        if cadence > 0, metrics.averageCadenceRPM == nil {
            metrics.averageCadenceRPM = cadence
            metrics.maxCadenceRPM = cadence
        }
        if power > 0, metrics.averageCyclingPowerWatts == nil {
            metrics.averageCyclingPowerWatts = power
            metrics.maxCyclingPowerWatts = power
        }
        currentRide.metrics = metrics
    }
}
