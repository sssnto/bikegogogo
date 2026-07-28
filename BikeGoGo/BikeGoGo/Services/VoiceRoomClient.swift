import AVFAudio
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
    var audioStatus: String
    var isLocal: Bool
}

@MainActor
final class VoiceRoomClient: NSObject, ObservableObject, RoomDelegate, @unchecked Sendable {
    @Published private(set) var status: VoiceConnectionStatus = .disconnected
    @Published private(set) var isConnected = false
    @Published private(set) var isMuted = false
    @Published private(set) var participants: [VoiceParticipantSnapshot] = []
    @Published private(set) var latestTokenResponse: VoiceTokenResponse?
    @Published private(set) var audioRouteName = "正在准备音频"
    @Published private(set) var errorMessage: String?

    private let tokenService = VoiceTokenService()
    private lazy var room = Room(delegate: self)

    override init() {
        super.init()
        AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false
        AudioManager.shared.audioSession.isSpeakerOutputPreferred = true
    }

    func join(
        groupID: String,
        accessToken: String?
    ) async {
        guard status == .disconnected else { return }
        guard let accessToken else {
            errorMessage = "请先建立 BikeGoGo 账户，再加入语音。"
            return
        }

        status = .connecting
        errorMessage = nil

        do {
            guard await requestMicrophonePermission() else {
                throw VoiceAudioError.microphonePermissionDenied
            }
            try configureAudioSession()
            let response = try await tokenService.token(
                groupID: groupID,
                accessToken: accessToken
            )
            latestTokenResponse = response

            try await room.connect(url: response.url.absoluteString, token: response.token)
            let microphonePublication = try await room.localParticipant.setMicrophone(
                enabled: true
            )
            guard microphonePublication != nil,
                  room.localParticipant.audioTracks.contains(where: {
                      $0.source == .microphone && !$0.isMuted
                  }) else {
                throw VoiceAudioError.microphoneTrackUnavailable
            }

            status = .connected
            isConnected = true
            isMuted = false
            refreshParticipants()
        } catch {
            await room.disconnect()
            deactivateAudioSession()
            status = .disconnected
            isConnected = false
            participants = []
            errorMessage = "加入语音失败：\(error.localizedDescription)"
        }
    }

    func leave() async {
        await room.disconnect()
        deactivateAudioSession()
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
            let microphoneEnabled = room.localParticipant.audioTracks.contains {
                $0.source == .microphone && !$0.isMuted
            }
            isMuted = !microphoneEnabled
            if !muted, !microphoneEnabled {
                throw VoiceAudioError.microphoneTrackUnavailable
            }
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

    private func requestMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await AVAudioApplication.requestRecordPermission()
        @unknown default:
            return false
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetoothHFP, .allowBluetoothA2DP, .defaultToSpeaker]
        )
        try session.setActive(true)
        updateAudioRoute()
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
        audioRouteName = "音频已关闭"
    }

    private func updateAudioRoute() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        audioRouteName = outputs.map(\.portName).joined(separator: "、")
        if audioRouteName.isEmpty {
            audioRouteName = "系统默认音频设备"
        }
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
            audioStatus: audioStatus(for: participant, isLocal: isLocal),
            isLocal: isLocal
        )
    }

    private func audioStatus(for participant: Participant, isLocal: Bool) -> String {
        guard let publication = participant.audioTracks.first(where: {
            $0.source == .microphone
        }) else {
            return isLocal ? "麦克风未发布" : "等待对方麦克风"
        }
        if publication.isMuted {
            return "麦克风已静音"
        }
        if isLocal || publication.isSubscribed {
            return isLocal ? "麦克风已发送" : "语音已接收"
        }
        return "正在订阅语音"
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

    nonisolated func room(
        _ room: Room,
        participant: RemoteParticipant,
        didSubscribeTrack publication: RemoteTrackPublication
    ) {
        Task { @MainActor in
            updateAudioRoute()
            refreshParticipants()
        }
    }

    nonisolated func room(
        _ room: Room,
        participant: RemoteParticipant,
        didFailToSubscribeTrackWithSid trackSid: Track.Sid,
        error: LiveKitError
    ) {
        Task { @MainActor in
            errorMessage = "接收 \(participant.name ?? "骑友") 的语音失败，请退出后重新呼叫。"
            refreshParticipants()
        }
    }
}

private enum VoiceAudioError: LocalizedError {
    case microphonePermissionDenied
    case microphoneTrackUnavailable

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "麦克风权限未开启，请到“设置 > 隐私与安全性 > 麦克风”允许 BikeGoGo 使用麦克风。"
        case .microphoneTrackUnavailable:
            "麦克风音轨没有成功发送，请检查系统麦克风权限和蓝牙耳机连接。"
        }
    }
}
