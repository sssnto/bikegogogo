import BikeGoGoCore
import SwiftUI

struct VoiceRoomView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            List {
                Section("语音房间") {
                    HStack {
                        Label(appState.voiceClient.latestTokenResponse?.roomName ?? appState.voiceRoom.roomName, systemImage: "waveform.circle")
                        Spacer()
                        Text(appState.voiceClient.status.title)
                            .foregroundStyle(appState.voiceClient.isConnected ? .green : .secondary)
                    }

                    Button {
                        Task {
                            if appState.voiceClient.isConnected {
                                await appState.leaveVoiceRoom()
                            } else {
                                await appState.joinVoiceRoom()
                            }
                        }
                    } label: {
                        Label(
                            appState.voiceClient.isConnected ? "退出语音" : "加入语音",
                            systemImage: appState.voiceClient.isConnected ? "phone.down.fill" : "phone.fill"
                        )
                    }
                    .disabled(
                        appState.voiceClient.status == .connecting
                            || appState.voiceClient.status == .reconnecting
                    )

                    Button {
                        Task {
                            await appState.toggleMute()
                        }
                    } label: {
                        Label(
                            appState.voiceClient.isMuted ? "解除静音" : "静音",
                            systemImage: appState.voiceClient.isMuted ? "mic.slash.fill" : "mic.fill"
                        )
                    }
                    .disabled(!appState.voiceClient.isConnected)
                }

                Section("成员") {
                    if appState.voiceClient.participants.isEmpty {
                        Text("加入语音后显示在线成员")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(appState.voiceClient.participants) { participant in
                        HStack(spacing: 12) {
                            Image(systemName: participant.isMuted ? "mic.slash.circle" : "mic.circle")
                                .foregroundStyle(participant.isSpeaking ? .green : .secondary)
                            VStack(alignment: .leading) {
                                Text(participant.isLocal ? "\(participant.displayName)（我）" : participant.displayName)
                                Text(participant.connectionQuality)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("小队语音")
            .alert(
                "语音连接",
                isPresented: Binding(
                    get: { appState.voiceClient.errorMessage != nil },
                    set: { if !$0 { appState.voiceClient.dismissError() } }
                )
            ) {
                Button("知道了") {
                    appState.voiceClient.dismissError()
                }
            } message: {
                Text(appState.voiceClient.errorMessage ?? "")
            }
        }
    }
}
