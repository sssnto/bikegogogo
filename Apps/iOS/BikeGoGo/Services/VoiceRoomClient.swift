import Foundation

@MainActor
final class VoiceRoomClient: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var isMuted = false
    @Published private(set) var latestTokenResponse: VoiceTokenResponse?

    private let tokenService = VoiceTokenService()

    func join(groupID: String, identity: String, displayName: String) async {
        do {
            let response = try await tokenService.token(
                groupID: groupID,
                identity: identity,
                displayName: displayName
            )
            latestTokenResponse = response
            // TODO: Pass response.url and response.token to LiveKit Room.connect after adding the SDK to the Xcode target.
            print("Prepared LiveKit room: \(response.roomName)")
            isConnected = true
        } catch {
            print("Preparing voice room failed: \(error.localizedDescription)")
            isConnected = false
        }
    }

    func leave() async {
        // TODO: Disconnect LiveKit room.
        isConnected = false
        latestTokenResponse = nil
    }

    func setMuted(_ muted: Bool) {
        // TODO: Publish local participant microphone state to LiveKit.
        isMuted = muted
    }
}
