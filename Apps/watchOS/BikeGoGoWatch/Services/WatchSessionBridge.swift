import Combine
import Foundation
import WatchConnectivity

final class WatchSessionBridge: NSObject, ObservableObject {
    @Published private(set) var isMuted = false
    @Published private(set) var remoteRideState = "idle"

    var onRideStateReceived: ((String) -> Void)?

    private var session: WCSession? {
        WCSession.isSupported() ? .default : nil
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    func sendRideState(_ state: String) {
        send(["type": "rideState", "state": state])
    }

    func sendWorkoutMetrics(
        elapsedSeconds: TimeInterval,
        distanceMeters: Double,
        heartRate: Double,
        speedMetersPerSecond: Double,
        activeEnergyKilocalories: Double,
        cadenceRPM: Double,
        cyclingPowerWatts: Double
    ) {
        send([
            "type": "workoutMetrics",
            "elapsedSeconds": elapsedSeconds,
            "distanceMeters": distanceMeters,
            "heartRate": heartRate,
            "speedMetersPerSecond": speedMetersPerSecond,
            "activeEnergyKilocalories": activeEnergyKilocalories,
            "cadenceRPM": cadenceRPM,
            "cyclingPowerWatts": cyclingPowerWatts
        ])
    }

    func toggleMute() {
        isMuted.toggle()
        send(["type": "voiceMute", "isMuted": isMuted])
    }

    private func send(_ payload: [String: Any]) {
        guard let session else { return }

        try? session.updateApplicationContext(payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                print("iPhone message failed: \(error.localizedDescription)")
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    private func receive(_ payload: [String: Any]) {
        Task { @MainActor in
            switch payload["type"] as? String {
            case "rideState":
                guard let state = payload["state"] as? String else { return }
                remoteRideState = state
                onRideStateReceived?(state)
            case "voiceMute":
                guard let muted = payload["isMuted"] as? Bool else { return }
                isMuted = muted
            default:
                break
            }
        }
    }
}

extension WatchSessionBridge: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            print("WatchConnectivity activation failed: \(error.localizedDescription)")
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        receive(userInfo)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receive(applicationContext)
    }
}
