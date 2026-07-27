import BikeGoGoCore
import Combine
import CoreLocation
import Foundation

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
    @Published private(set) var watchHeartRate = 0.0
    @Published var rideAlertMessage: String?
    @Published private(set) var isSyncingRides = false
    @Published private(set) var rideSyncMessage: String?
    @Published private(set) var lastRideSyncAt: Date?

    private let rideStore = LocalRideStore()
    private let rideCloudClient = RideCloudClient()
    let rideRecorder = LocationRideRecorder()
    let voiceClient = VoiceRoomClient()
    let accountClient = AccountClient()
    let watchBridge = WatchSessionBridge()
    private let watchWorkoutLauncher = WatchWorkoutLauncher()
    private let localUserID: String
    private let localDisplayName: String
    private var cancellables: Set<AnyCancellable> = []
    private var pendingStartAfterAuthorization = false
    private var activeElapsedSeconds: TimeInterval = 0
    private var activeSegmentStartedAt: Date?
    private var recorderNeedsRestart = false

    init() {
        let identityKey = "bikegogo.localVoiceIdentity"
        if let storedIdentity = UserDefaults.standard.string(forKey: identityKey) {
            localUserID = storedIdentity
        } else {
            let newIdentity = UUID().uuidString.lowercased()
            UserDefaults.standard.set(newIdentity, forKey: identityKey)
            localUserID = newIdentity
        }
        localDisplayName = "骑友-\(localUserID.prefix(4).uppercased())"
        accountClient.beforeSignOut = { [weak accountClient] in
            guard let accessToken = accountClient?.accessToken else { return }
            await PushNotificationManager.shared.unregisterCurrentToken(
                accessToken: accessToken
            )
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
    }

    func bootstrap() async {
        rideRecorder.onPointsChanged = { [weak self] points in
            Task { @MainActor in
                guard let self else { return }
                self.currentRide.points = points
                self.currentRide.metrics = RideStatisticsCalculator.metrics(for: points)
                self.currentRide.metrics.elapsedDurationSeconds = self.rideElapsedDuration()
                await self.persistActiveRide()
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
        watchBridge.onWorkoutMetricsReceived = { [weak self] elapsed, distance, heartRate, speed in
            self?.handleWatchMetrics(
                elapsed: elapsed,
                distance: distance,
                heartRate: heartRate,
                speed: speed
            )
        }

        await accountClient.bootstrap(defaultDisplayName: localDisplayName)
        await PushNotificationManager.shared.requestAuthorization()
        await loadStoredRides()
        await syncRides()
        watchBridge.activate()
    }

    func requestRidePermissions() {
        rideRecorder.requestAuthorization()
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
        recorderNeedsRestart = false
        currentRide = RideSession(
            title: "本次骑行",
            state: .recording,
            source: .iPhone,
            startedAt: now
        )
        rideRecorder.start()
        watchBridge.sendRideState(.recording)
        Task {
            try? await watchWorkoutLauncher.startOutdoorCycling()
            await persistActiveRide()
        }
    }

    func pauseRide() {
        activeElapsedSeconds = rideElapsedDuration()
        activeSegmentStartedAt = nil
        currentRide.state = .paused
        currentRide.metrics.elapsedDurationSeconds = activeElapsedSeconds
        rideRecorder.pause()
        watchBridge.sendRideState(.paused)
        Task {
            await persistActiveRide()
        }
    }

    func resumeRide() {
        activeSegmentStartedAt = Date()
        currentRide.state = .recording
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
        activeElapsedSeconds = rideElapsedDuration()
        activeSegmentStartedAt = nil
        currentRide.state = .finished
        currentRide.endedAt = Date()
        currentRide.points = rideRecorder.points
        currentRide.metrics = RideStatisticsCalculator.metrics(for: currentRide.points)
        currentRide.metrics.elapsedDurationSeconds = activeElapsedSeconds
        rideRecorder.stop()

        if !currentRide.points.isEmpty {
            recentRides.insert(currentRide, at: 0)
            Task {
                await saveRecentRides()
                await syncRides()
            }
        }
        Task {
            try? await rideStore.clearActiveRide()
        }
        watchBridge.sendRideState(.finished)
    }

    func discardCurrentRide() {
        rideRecorder.stop()
        currentRide = RideSession(
            title: "准备开始骑行",
            state: .idle,
            source: .iPhone,
            points: []
        )
        activeElapsedSeconds = 0
        activeSegmentStartedAt = nil
        recorderNeedsRestart = false
        Task {
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

    func joinVoiceRoom(roomID: String) async {
        await voiceClient.join(
            groupID: roomID,
            accessToken: accountClient.accessToken
        )
        voiceRoom.isJoined = voiceClient.isConnected
    }

    func leaveVoiceRoom() async {
        await voiceClient.leave()
        voiceRoom.isJoined = false
    }

    func toggleMute() async {
        await voiceClient.setMuted(!voiceClient.isMuted)
        voiceRoom.isMuted = voiceClient.isMuted
        watchBridge.sendMuteState(voiceClient.isMuted)
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

    func deleteRide(_ ride: RideSession) async {
        guard let accessToken = accountClient.accessToken else { return }

        do {
            try await rideCloudClient.delete(rideID: ride.id, accessToken: accessToken)
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
        speed: Double
    ) {
        guard currentRide.state == .recording || currentRide.state == .paused else { return }

        watchHeartRate = heartRate
        if !currentRide.points.isEmpty, heartRate > 0 {
            currentRide.points[currentRide.points.count - 1].heartRateBeatsPerMinute = Int(heartRate)
        }

        var metrics = RideStatisticsCalculator.metrics(for: currentRide.points)
        metrics.elapsedDurationSeconds = max(rideElapsedDuration(), elapsed)
        metrics.distanceMeters = max(metrics.distanceMeters, distance)
        metrics.maxSpeedMetersPerSecond = max(metrics.maxSpeedMetersPerSecond, speed)
        if metrics.movingDurationSeconds == 0, elapsed > 0 {
            metrics.averageSpeedMetersPerSecond = distance / elapsed
        }
        currentRide.metrics = metrics
    }
}
