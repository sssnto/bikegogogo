import BikeGoGoCore
import Foundation
import WatchConnectivity

final class WatchSessionBridge: NSObject, WCSessionDelegate {
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

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                print("Watch message failed: \(error.localizedDescription)")
            }
        } else {
            session.transferUserInfo(payload)
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
}

