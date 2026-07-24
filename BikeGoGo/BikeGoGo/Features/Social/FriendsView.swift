import BikeGoGoCore
import SwiftUI

struct FriendsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            List {
                Section("当前小队") {
                    Text(appState.group.name)
                        .font(.headline)
                    ForEach(appState.group.members) { friend in
                        HStack {
                            Image(systemName: friend.isRiding ? "bicycle.circle.fill" : "person.circle")
                                .foregroundStyle(friend.isRiding ? .green : .secondary)
                            Text(friend.displayName)
                            Spacer()
                            Text(friend.isRiding ? "骑行中" : "空闲")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("添加好友") {
                    Button {
                    } label: {
                        Label("生成我的邀请码", systemImage: "qrcode")
                    }

                    Button {
                    } label: {
                        Label("输入好友邀请码", systemImage: "person.badge.plus")
                    }
                }
            }
            .navigationTitle("好友")
        }
    }
}
