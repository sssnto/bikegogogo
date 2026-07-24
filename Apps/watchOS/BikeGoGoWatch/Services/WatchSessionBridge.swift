import Foundation
import WatchConnectivity

final class WatchSessionBridge: NSObject, ObservableObject {
    @Published private(set) var isMuted = false

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

    func toggleMute() {
        isMuted.toggle()
        send(["type": "voiceMute", "isMuted": isMuted])
    }

    private func send(_ payload: [String: Any]) {
        guard let session else { return }

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                print("iPhone message failed: \(error.localizedDescription)")
            }
        } else {
            session.transferUserInfo(payload)
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
}

