import BikeGoGoCore
import SwiftUI

private enum VoiceScope: String, CaseIterable, Identifiable {
    case group = "小队"
    case friend = "好友"

    var id: Self { self }
}

struct VoiceRoomView: View {
    @EnvironmentObject private var appState: AppState
    @State private var scope: VoiceScope = .group
    @State private var selectedGroupID: String?
    @State private var selectedFriendID: String?
    @State private var isCreatingGroup = false

    private var selectedTargetID: String? {
        scope == .group ? selectedGroupID : selectedFriendID
    }

    private var selectedTargetName: String? {
        switch scope {
        case .group:
            appState.accountClient.groups.first { $0.id == selectedGroupID }?.name
        case .friend:
            appState.accountClient.friends.first { $0.id == selectedFriendID }?.displayName
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("语音房间") {
                    Picker("通话范围", selection: $scope) {
                        ForEach(VoiceScope.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(appState.voiceClient.isConnected)

                    targetPicker

                    HStack {
                        Label(
                            selectedTargetName.map { "与 \($0) 通话" } ?? "请选择通话对象",
                            systemImage: "waveform.circle"
                        )
                        Spacer()
                        Text(appState.voiceClient.status.title)
                            .foregroundStyle(appState.voiceClient.isConnected ? .green : .secondary)
                    }

                    Button {
                        Task {
                            if appState.voiceClient.isConnected {
                                await appState.leaveVoiceRoom()
                            } else if let selectedTargetID {
                                await appState.joinVoiceRoom(roomID: selectedTargetID)
                            }
                        }
                    } label: {
                        Label(
                            appState.voiceClient.isConnected ? "退出语音" : "加入语音",
                            systemImage: appState.voiceClient.isConnected
                                ? "phone.down.fill"
                                : "phone.fill"
                        )
                    }
                    .disabled(
                        appState.voiceClient.status == .connecting
                            || appState.voiceClient.status == .reconnecting
                            || (!appState.voiceClient.isConnected && selectedTargetID == nil)
                    )

                    Button {
                        Task { await appState.toggleMute() }
                    } label: {
                        Label(
                            appState.voiceClient.isMuted ? "解除静音" : "静音",
                            systemImage: appState.voiceClient.isMuted
                                ? "mic.slash.fill"
                                : "mic.fill"
                        )
                    }
                    .disabled(!appState.voiceClient.isConnected)
                }

                Section("在线成员") {
                    if appState.voiceClient.participants.isEmpty {
                        Text("加入语音后显示在线成员")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(appState.voiceClient.participants) { participant in
                        HStack(spacing: 12) {
                            Image(systemName: participant.isMuted ? "mic.slash.circle" : "mic.circle")
                                .foregroundStyle(participant.isSpeaking ? .green : .secondary)
                            VStack(alignment: .leading) {
                                Text(
                                    participant.isLocal
                                        ? "\(participant.displayName)（我）"
                                        : participant.displayName
                                )
                                Text(participant.connectionQuality)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }

                Section("我的小队") {
                    if appState.accountClient.groups.isEmpty {
                        Text("创建小队后，可以邀请已互相同意的好友加入多人语音。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appState.accountClient.groups) { group in
                            NavigationLink {
                                GroupDetailView(
                                    account: appState.accountClient,
                                    groupID: group.id
                                )
                            } label: {
                                HStack {
                                    Label(group.name, systemImage: "person.3.fill")
                                    Spacer()
                                    Text("\(group.members.count) 人")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("骑行语音")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCreatingGroup = true
                    } label: {
                        Image(systemName: "person.3.sequence.fill")
                    }
                    .disabled(appState.accountClient.currentUser == nil)
                    .accessibilityLabel("创建小队")
                }
            }
            .onAppear { chooseAvailableTargets() }
            .onChange(of: appState.accountClient.groups) { _, _ in
                chooseAvailableTargets()
            }
            .onChange(of: appState.accountClient.friends) { _, _ in
                chooseAvailableTargets()
            }
            .sheet(isPresented: $isCreatingGroup) {
                CreateGroupSheet(account: appState.accountClient)
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

    @ViewBuilder
    private var targetPicker: some View {
        switch scope {
        case .group:
            Picker("选择小队", selection: $selectedGroupID) {
                Text("请选择").tag(nil as String?)
                ForEach(appState.accountClient.groups) { group in
                    Text(group.name).tag(Optional(group.id))
                }
            }
            .disabled(appState.voiceClient.isConnected)

        case .friend:
            Picker("选择好友", selection: $selectedFriendID) {
                Text("请选择").tag(nil as String?)
                ForEach(appState.accountClient.friends) { friend in
                    Text(friend.displayName).tag(Optional(friend.id))
                }
            }
            .disabled(appState.voiceClient.isConnected)
        }
    }

    private func chooseAvailableTargets() {
        let groups = appState.accountClient.groups
        let friends = appState.accountClient.friends

        if !groups.contains(where: { $0.id == selectedGroupID }) {
            selectedGroupID = groups.first?.id
        }
        if !friends.contains(where: { $0.id == selectedFriendID }) {
            selectedFriendID = friends.first?.id
        }
        if groups.isEmpty, !friends.isEmpty {
            scope = .friend
        } else if friends.isEmpty, !groups.isEmpty {
            scope = .group
        }
    }
}

private struct CreateGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var account: AccountClient
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("小队名称", text: $name)
                    .onChange(of: name) { _, newValue in
                        name = String(newValue.prefix(40))
                    }
            }
            .navigationTitle("创建小队")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        Task {
                            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            if await account.createGroup(name: trimmed) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).count < 2
                            || account.isWorking
                    )
                }
            }
        }
    }
}

private struct GroupDetailView: View {
    @ObservedObject var account: AccountClient
    let groupID: String
    @State private var showingDeleteConfirmation = false

    private var group: AppGroup? {
        account.groups.first { $0.id == groupID }
    }

    var body: some View {
        List {
            if let group {
                GroupMembersSection(account: account, group: group)
                if group.isOwner {
                    GroupInviteSection(account: account, group: group)
                }
                GroupActionsSection(
                    account: account,
                    group: group,
                    showingDeleteConfirmation: $showingDeleteConfirmation
                )
            } else {
                ContentUnavailableView(
                    "小队不存在",
                    systemImage: "person.3.sequence",
                    description: Text("这个小队可能已经被解散。")
                )
            }
        }
        .navigationTitle(group?.name ?? "小队")
        .confirmationDialog(
            "确定解散这个小队？",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("解散小队", role: .destructive) {
                Task { await account.deleteGroup(groupID: groupID) }
            }
        } message: {
            Text("成员将无法继续进入这个小队的语音房间。")
        }
    }
}

private struct GroupMembersSection: View {
    @ObservedObject var account: AccountClient
    let group: AppGroup

    var body: some View {
        Section("成员 \(group.members.count)") {
            ForEach(group.members) { member in
                GroupMemberRow(account: account, group: group, member: member)
            }
        }
    }
}

private struct GroupMemberRow: View {
    @ObservedObject var account: AccountClient
    let group: AppGroup
    let member: AppUser

    private var isOwner: Bool {
        member.id == group.owner.id
    }

    var body: some View {
        HStack {
            Image(systemName: isOwner
                ? "person.crop.circle.badge.checkmark"
                : "person.crop.circle")
                .foregroundStyle(isOwner ? Color.accentColor : Color.secondary)
            Text(member.displayName)
            Spacer()
            if isOwner {
                Text("创建者")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if group.isOwner {
                Button(role: .destructive) {
                    Task {
                        await account.removeMember(groupID: group.id, userID: member.id)
                    }
                } label: {
                    Image(systemName: "person.badge.minus")
                }
                .buttonStyle(.borderless)
                .disabled(account.isWorking)
                .accessibilityLabel("移出 \(member.displayName)")
            }
        }
    }
}

private struct GroupInviteSection: View {
    @ObservedObject var account: AccountClient
    let group: AppGroup

    private var availableFriends: [AppUser] {
        account.friends.filter { friend in
            !group.members.contains(where: { $0.id == friend.id })
        }
    }

    var body: some View {
        Section("邀请好友") {
            if availableFriends.isEmpty {
                Text("所有好友都已加入，或还没有可邀请的好友。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(availableFriends) { friend in
                    Button {
                        Task {
                            await account.addMember(groupID: group.id, userID: friend.id)
                        }
                    } label: {
                        Label(friend.displayName, systemImage: "person.badge.plus")
                    }
                    .disabled(account.isWorking)
                }
            }
        }
    }
}

private struct GroupActionsSection: View {
    @ObservedObject var account: AccountClient
    let group: AppGroup
    @Binding var showingDeleteConfirmation: Bool

    var body: some View {
        Section {
            if group.isOwner {
                Button("解散小队", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            } else {
                Button("退出小队", role: .destructive) {
                    Task { await account.leaveGroup(groupID: group.id) }
                }
            }
        }
        .disabled(account.isWorking)
    }
}
