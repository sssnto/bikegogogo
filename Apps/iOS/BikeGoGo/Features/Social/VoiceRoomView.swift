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
                        Text(appState.voiceRoom.isJoined ? "已加入" : "未加入")
                            .foregroundStyle(appState.voiceRoom.isJoined ? .green : .secondary)
                    }

                    Button {
                        Task {
                            if appState.voiceRoom.isJoined {
                                await appState.leaveVoiceRoom()
                            } else {
                                await appState.joinVoiceRoom()
                            }
                        }
                    } label: {
                        Label(appState.voiceRoom.isJoined ? "退出语音" : "加入语音", systemImage: appState.voiceRoom.isJoined ? "phone.down.fill" : "phone.fill")
                    }

                    Button {
                        appState.toggleMute()
                    } label: {
                        Label(appState.voiceRoom.isMuted ? "解除静音" : "静音", systemImage: appState.voiceRoom.isMuted ? "mic.slash.fill" : "mic.fill")
                    }
                    .disabled(!appState.voiceRoom.isJoined)
                }

                Section("成员") {
                    ForEach(appState.voiceRoom.participants) { participant in
                        HStack(spacing: 12) {
                            Image(systemName: participant.isMuted ? "mic.slash.circle" : "mic.circle")
                                .foregroundStyle(participant.isSpeaking ? .green : .secondary)
                            VStack(alignment: .leading) {
                                Text(participant.displayName)
                                Text(participant.connectionQuality.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("小队语音")
        }
    }
}
