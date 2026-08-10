import Foundation
import SwiftUI

struct RootView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            RideTrackingView()
                .tabItem {
                    Label("骑行", systemImage: "bicycle")
                }

            VoiceRoomView()
                .tabItem {
                    Label("语音", systemImage: "waveform")
                }

            FriendsView()
                .tabItem {
                    Label("我的", systemImage: "person.crop.circle")
                }

            RideHistoryView()
                .tabItem {
                    Label("历史", systemImage: "clock.arrow.circlepath")
                }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if appState.hasActiveVoiceCall,
               appState.incomingVoiceInvitation == nil {
                VoiceCallStatusBar()
                    .environmentObject(appState)
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { appState.incomingVoiceInvitation != nil },
                set: { _ in }
            )
        ) {
            if let invitation = appState.incomingVoiceInvitation {
                IncomingVoiceCallView(invitation: invitation)
                    .environmentObject(appState)
            }
        }
        .alert(
            "小队紧急求助",
            isPresented: Binding(
                get: { appState.incomingTeamSOS != nil },
                set: { if !$0 { appState.dismissIncomingTeamSOS() } }
            )
        ) {
            if let event = appState.incomingTeamSOS,
               let mapURL = mapURL(for: event) {
                Button("在地图中查看") {
                    appState.dismissIncomingTeamSOS()
                    openURL(mapURL)
                }
            }
            Button("知道了", role: .cancel) {
                appState.dismissIncomingTeamSOS()
            }
        } message: {
            if let event = appState.incomingTeamSOS {
                Text("\(event.senderName) 在“\(event.groupName)”中发出求助，请尽快联系。")
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await appState.refreshIncomingVoiceInvitations()
            }
        }
    }

    private func mapURL(for event: TeamSOSPushEvent) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.path = "/"
        components.queryItems = [
            URLQueryItem(name: "ll", value: "\(event.latitude),\(event.longitude)"),
            URLQueryItem(name: "q", value: "\(event.senderName) 的求助位置")
        ]
        return components.url
    }
}

private struct VoiceCallStatusBar: View {
    @EnvironmentObject private var appState: AppState

    private var tint: Color {
        switch appState.voiceCallPhase {
        case .connected:
            .green
        case .reconnecting:
            .yellow
        case .idle:
            .secondary
        case .preparing, .calling, .connecting, .syncingAudio, .waitingForParticipants:
            .orange
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.16))
                    .frame(width: 36, height: 36)
                if appState.voiceCallPhase.showsProgress {
                    ProgressView()
                        .controlSize(.small)
                        .tint(tint)
                } else {
                    Image(systemName: appState.voiceCallPhase.systemImage)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(tint)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(appState.voiceCallPhase.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Text(appState.voiceCallStatusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if appState.voiceClient.isConnected {
                Button {
                    Task { await appState.toggleMute() }
                } label: {
                    Image(systemName: appState.voiceClient.isMuted ? "mic.slash.fill" : "mic.fill")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .foregroundStyle(appState.voiceClient.isMuted ? .orange : .primary)
                .accessibilityLabel(appState.voiceClient.isMuted ? "解除静音" : "静音")
            }

            Button {
                Task { await appState.leaveVoiceRoom() }
            } label: {
                Image(systemName: "phone.down.fill")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .disabled(appState.voiceCallPhase == .preparing)
            .accessibilityLabel(
                appState.voiceCallPhase == .connected ? "结束语音" : "取消呼叫"
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .animation(.easeInOut(duration: 0.2), value: appState.voiceCallPhase)
    }
}

private struct IncomingVoiceCallView: View {
    @EnvironmentObject private var appState: AppState
    let invitation: VoiceInvitation

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: invitation.isGroupCall ? "person.3.fill" : "person.fill")
                .font(.system(size: 52))
                .foregroundStyle(.white)
                .frame(width: 116, height: 116)
                .background(.teal, in: Circle())

            Text(invitation.caller.displayName)
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
                .padding(.top, 30)

            Text(invitation.isGroupCall ? invitation.targetName : "BikeGoGo 语音")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 8)

            Spacer()

            HStack {
                callAction(
                    title: "拒绝",
                    systemImage: "phone.down.fill",
                    color: .red
                ) {
                    await appState.declineIncomingVoiceInvitation()
                }

                Spacer()

                callAction(
                    title: "接听",
                    systemImage: "phone.fill",
                    color: .green
                ) {
                    await appState.acceptIncomingVoiceInvitation()
                }
            }
            .padding(.horizontal, 56)
            .padding(.bottom, 72)
        }
        .background(Color.black.ignoresSafeArea())
        .interactiveDismissDisabled()
        .task(id: invitation.id) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let expirationDate = formatter.date(from: invitation.expiresAt) else {
                return
            }
            let delay = max(expirationDate.timeIntervalSinceNow, 0)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            appState.dismissIncomingVoiceInvitationIfExpired(invitation.id)
        }
    }

    private func callAction(
        title: String,
        systemImage: String,
        color: Color,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            VStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(color, in: Circle())
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
        }
        .disabled(appState.isHandlingVoiceInvitation)
    }
}
