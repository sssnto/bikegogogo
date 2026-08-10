import AVFAudio
import Combine
import Foundation
import LiveKit
import LiveKitKrispNoiseFilter

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
    var isAudioReady: Bool
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
    @Published private(set) var noiseCancellationName = "Krisp 增强降噪待连接"
    @Published private(set) var hasHadRemoteParticipant = false
    @Published private(set) var errorMessage: String?

    var remoteParticipantCount: Int {
        participants.lazy.filter { !$0.isLocal }.count
    }

    var remoteAudioReadyCount: Int {
        participants.lazy.filter { !$0.isLocal && $0.isAudioReady }.count
    }

    var isLocalAudioReady: Bool {
        participants.first(where: \.isLocal)?.isAudioReady == true
    }

    private let tokenService = VoiceTokenService()
    private let krispProcessor = LiveKitKrispNoiseFilter()
    private lazy var room = Room(delegate: self)
    private var cancellables = Set<AnyCancellable>()
    private var connectionAttemptID: UUID?

    private static let outdoorCaptureOptions = AudioCaptureOptions(
        echoCancellation: true,
        autoGainControl: true,
        noiseSuppression: true,
        highpassFilter: true,
        typingNoiseDetection: false,
        echoCancellationMode: .automatic,
        autoGainControlMode: .automatic,
        noiseSuppressionMode: .automatic,
        highpassFilterMode: .software
    )

    private static let mobilePublishOptions = AudioPublishOptions(
        encoding: AudioEncoding(
            maxBitrate: 24_000,
            bitratePriority: .high,
            networkPriority: .high
        ),
        dtx: false,
        red: true
    )

    private static let mobileConnectOptions = ConnectOptions(
        reconnectAttempts: 20,
        reconnectAttemptDelay: 0.3,
        reconnectMaxDelay: 5,
        isDscpEnabled: true
    )

    private static let voiceRoomOptions = RoomOptions(
        defaultAudioCaptureOptions: outdoorCaptureOptions,
        defaultAudioPublishOptions: mobilePublishOptions,
        singlePeerConnection: true
    )

    override init() {
        super.init()
        AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = true
        AudioManager.shared.audioSession.isAutomaticDeactivationEnabled = true
        AudioManager.shared.audioSession.isSpeakerOutputPreferred = true
        krispProcessor.isEnabled = true
        AudioManager.shared.capturePostProcessingDelegate = krispProcessor
        room.add(delegate: krispProcessor)
        try? AudioManager.shared.set(microphoneMuteMode: .inputMixer)

        NotificationCenter.default.publisher(
            for: AVAudioSession.routeChangeNotification
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.updateAudioRoute()
        }
        .store(in: &cancellables)
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
        hasHadRemoteParticipant = false
        let attemptID = UUID()
        connectionAttemptID = attemptID

        do {
            guard await requestMicrophonePermission() else {
                throw VoiceAudioError.microphonePermissionDenied
            }
            let response = try await tokenService.token(
                groupID: groupID,
                accessToken: accessToken
            )
            latestTokenResponse = response

            try await room.connect(
                url: response.url.absoluteString,
                token: response.token,
                connectOptions: Self.mobileConnectOptions,
                roomOptions: Self.voiceRoomOptions
            )
            guard connectionAttemptID == attemptID else {
                await room.disconnect()
                return
            }
            let microphonePublication = try await room.localParticipant.setMicrophone(
                enabled: true,
                captureOptions: Self.outdoorCaptureOptions,
                publishOptions: Self.mobilePublishOptions
            )
            guard microphonePublication != nil,
                  room.localParticipant.audioTracks.contains(where: {
                      $0.source == .microphone && !$0.isMuted
                  }) else {
                throw VoiceAudioError.microphoneTrackUnavailable
            }
            guard connectionAttemptID == attemptID else {
                await room.disconnect()
                return
            }

            connectionAttemptID = nil
            updateAudioRoute()
            noiseCancellationName = "Krisp 增强降噪已启用"
            status = .connected
            isConnected = true
            isMuted = false
            refreshParticipants()
        } catch {
            let shouldPresentError = connectionAttemptID == attemptID
            if shouldPresentError {
                connectionAttemptID = nil
            }
            await room.disconnect()
            guard shouldPresentError else { return }
            status = .disconnected
            isConnected = false
            participants = []
            hasHadRemoteParticipant = false
            audioRouteName = "音频已关闭"
            noiseCancellationName = "Krisp 增强降噪待连接"
            errorMessage = "加入语音失败：\(error.localizedDescription)"
        }
    }

    func leave() async {
        connectionAttemptID = nil
        await room.disconnect()
        status = .disconnected
        isConnected = false
        isMuted = false
        participants = []
        hasHadRemoteParticipant = false
        latestTokenResponse = nil
        audioRouteName = "音频已关闭"
        noiseCancellationName = "Krisp 增强降噪待连接"
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
            noiseCancellationName = "Krisp 增强降噪初始化中"
        case .connected:
            status = .connected
            isConnected = true
        case .reconnecting:
            status = .reconnecting
        case .disconnecting, .disconnected:
            status = .disconnected
            isConnected = false
            noiseCancellationName = "Krisp 增强降噪待连接"
        @unknown default:
            status = .disconnected
            isConnected = false
            noiseCancellationName = "Krisp 增强降噪待连接"
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
        if snapshots.contains(where: { !$0.isLocal }) {
            hasHadRemoteParticipant = true
        }
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
        let microphonePublication = participant.audioTracks.first {
            $0.source == .microphone
        }
        return VoiceParticipantSnapshot(
            id: participant.identity?.stringValue ?? fallbackID,
            displayName: participant.name ?? participant.identity?.stringValue ?? "骑友",
            isMuted: !participant.isMicrophoneEnabled(),
            isSpeaking: participant.isSpeaking,
            connectionQuality: qualityTitle(participant.connectionQuality),
            audioStatus: audioStatus(for: participant, isLocal: isLocal),
            isAudioReady: microphonePublication.map {
                isLocal || $0.isSubscribed
            } ?? false,
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
