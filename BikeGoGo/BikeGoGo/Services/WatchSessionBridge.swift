import BikeGoGoCore
import Foundation
import WatchConnectivity

final class WatchSessionBridge: NSObject, WCSessionDelegate {
    var onRideStateReceived: ((RideState) -> Void)?
    var onMuteStateReceived: ((Bool) -> Void)?
    var onWorkoutMetricsReceived: ((TimeInterval, Double, Double, Double) -> Void)?

    private var session: WCSession? {
        WCSession.isSupported() ? .default : nil
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    func sendRideState(_ state: RideState) {
        send(["type": "rideState", "state": state.rawValue])
    }

    func sendMuteState(_ isMuted: Bool) {
        send(["type": "voiceMute", "isMuted": isMuted])
    }

    private func send(_ payload: [String: Any]) {
        guard let session else { return }

        try? session.updateApplicationContext(payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                print("Watch message failed: \(error.localizedDescription)")
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    private func receive(_ payload: [String: Any]) {
        Task { @MainActor in
            switch payload["type"] as? String {
            case "rideState":
                guard let rawState = payload["state"] as? String,
                      let state = RideState(rawValue: rawState) else { return }
                onRideStateReceived?(state)
            case "voiceMute":
                guard let muted = payload["isMuted"] as? Bool else { return }
                onMuteStateReceived?(muted)
            case "workoutMetrics":
                guard let elapsed = payload["elapsedSeconds"] as? Double,
                      let distance = payload["distanceMeters"] as? Double,
                      let heartRate = payload["heartRate"] as? Double,
                      let speed = payload["speedMetersPerSecond"] as? Double else { return }
                onWorkoutMetricsReceived?(elapsed, distance, heartRate, speed)
            default:
                break
            }
        }
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            print("Watch session activation failed: \(error.localizedDescription)")
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
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
