import BikeGoGoCore
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var currentRide = RideSession(
        title: "准备开始骑行",
        state: .idle,
        source: .iPhone,
        points: []
    )
    @Published var recentRides: [RideSession] = [SampleData.ride]
    @Published var group = SampleData.group
    @Published var voiceRoom = SampleData.voiceRoom

    private let rideStore = LocalRideStore()
    let rideRecorder = LocationRideRecorder()
    let voiceClient = VoiceRoomClient()
    let watchBridge = WatchSessionBridge()
    private let localUserID = "local-rider"
    private let localDisplayName = "BikeGoGo Rider"

    func bootstrap() async {
        await loadStoredRides()

        rideRecorder.onPointsChanged = { [weak self] points in
            Task { @MainActor in
                guard let self else { return }
                self.currentRide.points = points
                self.currentRide.metrics = RideStatisticsCalculator.metrics(for: points)
            }
        }

        watchBridge.activate()
    }

    func requestRidePermissions() {
        rideRecorder.requestAuthorization()
    }

    func startRide() {
        currentRide = RideSession(
            title: "本次骑行",
            state: .recording,
            source: .iPhone,
            startedAt: Date()
        )
        rideRecorder.start()
        watchBridge.sendRideState(.recording)
    }

    func pauseRide() {
        currentRide.state = .paused
        rideRecorder.pause()
        watchBridge.sendRideState(.paused)
    }

    func resumeRide() {
        currentRide.state = .recording
        rideRecorder.resume()
        watchBridge.sendRideState(.recording)
    }

    func finishRide() {
        currentRide.state = .finished
        currentRide.endedAt = Date()
        currentRide.points = rideRecorder.points
        currentRide.metrics = RideStatisticsCalculator.metrics(for: currentRide.points)
        rideRecorder.stop()

        if !currentRide.points.isEmpty {
            recentRides.insert(currentRide, at: 0)
            Task {
                await saveRecentRides()
            }
        }
        watchBridge.sendRideState(.finished)
    }

    func exportGPX(for ride: RideSession) async -> URL? {
        do {
            return try await rideStore.exportGPX(for: ride)
        } catch {
            print("GPX export failed: \(error.localizedDescription)")
            return nil
        }
    }

    func joinVoiceRoom() async {
        await voiceClient.join(
            groupID: group.id.uuidString,
            identity: localUserID,
            displayName: localDisplayName
        )
        voiceRoom.isJoined = voiceClient.isConnected
    }

    func leaveVoiceRoom() async {
        await voiceClient.leave()
        voiceRoom.isJoined = false
    }

    func toggleMute() {
        voiceClient.setMuted(!voiceRoom.isMuted)
        voiceRoom.isMuted.toggle()
        watchBridge.sendMuteState(voiceRoom.isMuted)
    }

    private func loadStoredRides() async {
        do {
            let storedRides = try await rideStore.loadRides()
            if !storedRides.isEmpty {
                recentRides = storedRides
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
}
