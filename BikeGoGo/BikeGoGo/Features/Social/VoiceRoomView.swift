import BikeGoGoCore
import SwiftUI

struct VoiceRoomView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedFriendID: String?

    private var selectedFriend: AppUser? {
        appState.accountClient.friends.first { $0.id == selectedFriendID }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("语音房间") {
                    HStack {
                        Label(
                            selectedFriend.map { "与 \($0.displayName) 通话" } ?? "选择一位好友",
                            systemImage: "waveform.circle"
                        )
                        Spacer()
                        Text(appState.voiceClient.status.title)
                            .foregroundStyle(appState.voiceClient.isConnected ? .green : .secondary)
                    }

                    Picker("通话好友", selection: $selectedFriendID) {
                        Text("请选择").tag(nil as String?)
                        ForEach(appState.accountClient.friends) { friend in
                            Text(friend.displayName).tag(Optional(friend.id))
                        }
                    }
                    .disabled(appState.voiceClient.isConnected)

                    Button {
                        Task {
                            if appState.voiceClient.isConnected {
                                await appState.leaveVoiceRoom()
                            } else if let selectedFriendID {
                                await appState.joinVoiceRoom(friendID: selectedFriendID)
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
                            || (!appState.voiceClient.isConnected && selectedFriendID == nil)
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
                    if appState.accountClient.friends.isEmpty {
                        Text("先在“我的”中与好友互相同意，才能建立语音。")
                            .foregroundStyle(.secondary)
                    }
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
            .navigationTitle("好友语音")
            .onAppear {
                if selectedFriendID == nil {
                    selectedFriendID = appState.accountClient.friends.first?.id
                }
            }
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
