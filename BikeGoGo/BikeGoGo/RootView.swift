import SwiftUI

struct RootView: View {
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
    }
}
