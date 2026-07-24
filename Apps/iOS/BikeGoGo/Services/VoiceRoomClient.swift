import Combine
import Foundation
import LiveKit

enum VoiceConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting

    var title: String {
        switch self {
        case .disconnected: "未加入"
        case .connecting: "连接中"
        case .connected: "已加入"
        case .reconnecting: "正在重连"
        }
    }
}

struct VoiceParticipantSnapshot: Identifiable, Equatable {
    var id: String
    var displayName: String
    var isMuted: Bool
    var isSpeaking: Bool
    var connectionQuality: String
    var isLocal: Bool
}

@MainActor
final class VoiceRoomClient: NSObject, ObservableObject, RoomDelegate, @unchecked Sendable {
    @Published private(set) var status: VoiceConnectionStatus = .disconnected
    @Published private(set) var isConnected = false
    @Published private(set) var isMuted = false
    @Published private(set) var participants: [VoiceParticipantSnapshot] = []
    @Published private(set) var latestTokenResponse: VoiceTokenResponse?
    @Published private(set) var errorMessage: String?

    private let tokenService = VoiceTokenService()
    private lazy var room = Room(delegate: self)

    func join(
        groupID: String,
        identity: String,
        displayName: String,
        accessToken: String?
    ) async {
        guard status == .disconnected else { return }

        status = .connecting
        errorMessage = nil

        do {
            let response = try await tokenService.token(
                groupID: groupID,
                identity: identity,
                displayName: displayName,
                accessToken: accessToken
            )
            latestTokenResponse = response

            try await room.connect(url: response.url.absoluteString, token: response.token)
            try await room.localParticipant.setMicrophone(enabled: true)

            status = .connected
            isConnected = true
            isMuted = false
            refreshParticipants()
        } catch {
            await room.disconnect()
            status = .disconnected
            isConnected = false
            participants = []
            errorMessage = "加入语音失败：\(error.localizedDescription)"
        }
    }

    func leave() async {
        await room.disconnect()
        status = .disconnected
        isConnected = false
        isMuted = false
        participants = []
        latestTokenResponse = nil
    }

    func setMuted(_ muted: Bool) async {
        guard isConnected else { return }

        do {
            try await room.localParticipant.setMicrophone(enabled: !muted)
            isMuted = muted
            refreshParticipants()
        } catch {
            errorMessage = "切换麦克风失败：\(error.localizedDescription)"
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    private func updateConnectionState(_ connectionState: ConnectionState) {
        switch connectionState {
        case .connecting:
            status = .connecting
        case .connected:
            status = .connected
            isConnected = true
        case .reconnecting:
            status = .reconnecting
        case .disconnecting, .disconnected:
            status = .disconnected
            isConnected = false
        @unknown default:
            status = .disconnected
            isConnected = false
        }
        refreshParticipants()
    }

    private func refreshParticipants() {
        guard isConnected else {
            participants = []
            return
        }

        let localParticipant = room.localParticipant
        var snapshots = [
            snapshot(for: localParticipant, fallbackID: "local", isLocal: true)
        ]
        snapshots.append(contentsOf: room.remoteParticipants.values.map {
            snapshot(for: $0, fallbackID: String(describing: $0.sid), isLocal: false)
        })
        participants = snapshots.sorted {
            if $0.isLocal != $1.isLocal { return $0.isLocal }
            return $0.displayName.localizedCompare($1.displayName) == .orderedAscending
        }
    }

    private func snapshot(
        for participant: Participant,
        fallbackID: String,
        isLocal: Bool
    ) -> VoiceParticipantSnapshot {
        VoiceParticipantSnapshot(
            id: participant.identity?.stringValue ?? fallbackID,
            displayName: participant.name ?? participant.identity?.stringValue ?? "骑友",
            isMuted: !participant.isMicrophoneEnabled(),
            isSpeaking: participant.isSpeaking,
            connectionQuality: qualityTitle(participant.connectionQuality),
            isLocal: isLocal
        )
    }

    private func qualityTitle(_ quality: ConnectionQuality) -> String {
        switch quality {
        case .unknown: "检测中"
        case .lost: "连接中断"
        case .poor: "网络较差"
        case .good: "网络良好"
        case .excellent: "网络优秀"
        @unknown default: "检测中"
        }
    }

    nonisolated func room(
        _ room: Room,
        didUpdateConnectionState connectionState: ConnectionState,
        from oldConnectionState: ConnectionState
    ) {
        Task { @MainActor in
            updateConnectionState(connectionState)
        }
    }

    nonisolated func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        Task { @MainActor in
            refreshParticipants()
        }
    }

    nonisolated func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        Task { @MainActor in
            refreshParticipants()
        }
    }

    nonisolated func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant]) {
        Task { @MainActor in
            refreshParticipants()
        }
    }

    nonisolated func room(
        _ room: Room,
        participant: Participant,
        didUpdateConnectionQuality quality: ConnectionQuality
    ) {
        Task { @MainActor in
            refreshParticipants()
        }
    }

    nonisolated func room(
        _ room: Room,
        participant: Participant,
        trackPublication: TrackPublication,
        didUpdateIsMuted isMuted: Bool
    ) {
        Task { @MainActor in
            refreshParticipants()
        }
    }
}
