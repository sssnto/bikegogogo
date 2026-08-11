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
    @State private var isCreatingGroup = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    callOverview

                    if appState.hasActiveVoiceCall {
                        activeCallControls
                        participantSection
                    } else {
                        targetDirectory
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("小队")
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
            .refreshable {
                await appState.accountClient.refresh(presentsErrors: false)
                await appState.refreshIncomingVoiceInvitations()
            }
            .task {
                await appState.accountClient.refresh(presentsErrors: false)
                await appState.refreshIncomingVoiceInvitations()
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
                Button("知道了") { appState.voiceClient.dismissError() }
            } message: {
                Text(appState.voiceClient.errorMessage ?? "")
            }
            .alert(
                "语音呼叫",
                isPresented: Binding(
                    get: { appState.voiceCallMessage != nil },
                    set: { if !$0 { appState.voiceCallMessage = nil } }
                )
            ) {
                Button("知道了") { appState.voiceCallMessage = nil }
            } message: {
                Text(appState.voiceCallMessage ?? "")
            }
        }
    }

    private var callOverview: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: BikeGoGoStyle.cornerRadius)
                    .fill(voiceStatusTint.opacity(0.14))
                    .frame(width: 56, height: 56)

                if appState.voiceCallPhase.showsProgress {
                    ProgressView()
                        .tint(voiceStatusTint)
                } else {
                    Image(systemName: appState.voiceCallPhase.systemImage)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(voiceStatusTint)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(callOverviewTitle)
                    .font(.title3.bold())
                    .lineLimit(1)
                Text(callOverviewDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Text(appState.voiceCallPhase.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(voiceStatusTint)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(voiceStatusTint.opacity(0.12), in: Capsule())
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: BikeGoGoStyle.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: BikeGoGoStyle.cornerRadius)
                .stroke(voiceStatusTint.opacity(appState.hasActiveVoiceCall ? 0.3 : 0.12))
        }
        .animation(.easeInOut(duration: 0.2), value: appState.voiceCallPhase)
    }

    private var callOverviewTitle: String {
        appState.activeVoiceCallContext?.targetName ?? "骑行语音"
    }

    private var callOverviewDetail: String {
        if appState.hasActiveVoiceCall {
            return appState.voiceCallStatusDetail
        }
        let groupCount = appState.accountClient.groups.count
        let friendCount = appState.accountClient.friends.count
        return "\(groupCount) 个小队 · \(friendCount) 位好友"
    }

    private var activeCallControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            VoiceSectionHeader(title: "通话控制", value: participantCountText)

            HStack(spacing: 12) {
                Button {
                    Task { await appState.toggleMute() }
                } label: {
                    Label(
                        appState.voiceClient.isMuted ? "解除静音" : "静音",
                        systemImage: appState.voiceClient.isMuted ? "mic.slash.fill" : "mic.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .buttonBorderShape(.roundedRectangle(radius: BikeGoGoStyle.cornerRadius))
                .tint(appState.voiceClient.isMuted ? BikeGoGoStyle.warning : BikeGoGoStyle.brand)
                .disabled(!appState.voiceClient.isConnected)

                Button(role: .destructive) {
                    Task { await appState.leaveVoiceRoom() }
                } label: {
                    Label(activeCallActionTitle, systemImage: "phone.down.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .buttonBorderShape(.roundedRectangle(radius: BikeGoGoStyle.cornerRadius))
                .tint(BikeGoGoStyle.danger)
            }

            if appState.voiceClient.isConnected {
                Divider()

                HStack(alignment: .top, spacing: 18) {
                    VoiceAudioInfo(
                        title: "音频输出",
                        value: appState.voiceClient.audioRouteName,
                        systemImage: "speaker.wave.2.fill"
                    )
                    VoiceAudioInfo(
                        title: "环境降噪",
                        value: appState.voiceClient.noiseCancellationName,
                        systemImage: "waveform.badge.minus"
                    )
                }
            }
        }
    }

    private var participantSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VoiceSectionHeader(
                title: "通话成员",
                value: "\(appState.voiceClient.participants.count) 人"
            )

            if appState.voiceClient.participants.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("正在同步成员状态")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(16)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: BikeGoGoStyle.cornerRadius))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(appState.voiceClient.participants.enumerated()), id: \.element.id) { index, participant in
                        VoiceParticipantRow(participant: participant)
                        if index < appState.voiceClient.participants.count - 1 {
                            Divider().padding(.leading, 60)
                        }
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: BikeGoGoStyle.cornerRadius))
            }
        }
    }

    private var targetDirectory: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("语音对象", selection: $scope) {
                ForEach(VoiceScope.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)

            switch scope {
            case .group:
                groupDirectory
            case .friend:
                friendDirectory
            }
        }
    }

    private var groupDirectory: some View {
        VStack(alignment: .leading, spacing: 12) {
            VoiceSectionHeader(
                title: "我的小队",
                value: "\(appState.accountClient.groups.count) 个"
            )

            if appState.accountClient.groups.isEmpty {
                VoiceEmptyState(
                    title: "暂无小队",
                    systemImage: "person.3.sequence",
                    actionTitle: "创建小队"
                ) {
                    isCreatingGroup = true
                }
            } else {
                ForEach(appState.accountClient.groups) { group in
                    HStack(spacing: 12) {
                        NavigationLink {
                            GroupDetailView(account: appState.accountClient, groupID: group.id)
                        } label: {
                            VoiceTargetLabel(
                                title: group.name,
                                subtitle: "\(group.members.count) 位成员",
                                systemImage: "person.3.fill"
                            )
                        }
                        .buttonStyle(.plain)

                        VoiceCallButton(name: group.name) {
                            await appState.startVoiceCall(targetID: group.id)
                        }
                    }
                    .padding(14)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: BikeGoGoStyle.cornerRadius))
                }
            }
        }
    }

    private var friendDirectory: some View {
        VStack(alignment: .leading, spacing: 12) {
            VoiceSectionHeader(
                title: "骑行好友",
                value: "\(appState.accountClient.friends.count) 位"
            )

            if appState.accountClient.friends.isEmpty {
                VoiceEmptyState(title: "暂无好友", systemImage: "person.crop.circle.badge.plus")
            } else {
                ForEach(appState.accountClient.friends) { friend in
                    HStack(spacing: 12) {
                        VoiceTargetLabel(
                            title: friend.displayName,
                            subtitle: "好友语音",
                            systemImage: "person.fill"
                        )

                        VoiceCallButton(name: friend.displayName) {
                            await appState.startVoiceCall(targetID: friend.id)
                        }
                    }
                    .padding(14)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: BikeGoGoStyle.cornerRadius))
                }
            }
        }
    }

    private var activeCallActionTitle: String {
        switch appState.voiceCallPhase {
        case .preparing, .calling, .connecting, .syncingAudio:
            "取消呼叫"
        case .connected, .reconnecting, .waitingForParticipants:
            "结束语音"
        case .idle:
            "结束语音"
        }
    }

    private var participantCountText: String {
        guard appState.voiceClient.isConnected else { return appState.voiceCallPhase.title }
        return "\(appState.voiceClient.remoteParticipantCount + 1) 人在线"
    }

    private var voiceStatusTint: Color {
        switch appState.voiceCallPhase {
        case .connected:
            BikeGoGoStyle.brand
        case .preparing, .calling, .connecting, .syncingAudio, .waitingForParticipants:
            BikeGoGoStyle.warning
        case .reconnecting:
            .yellow
        case .idle:
            .secondary
        }
    }
}

private struct VoiceSectionHeader: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct VoiceTargetLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(BikeGoGoStyle.brand)
                .frame(width: 42, height: 42)
                .background(BikeGoGoStyle.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: BikeGoGoStyle.cornerRadius))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

private struct VoiceCallButton: View {
    let name: String
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: "phone.fill")
                .font(.headline)
                .frame(width: 42, height: 42)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: BikeGoGoStyle.cornerRadius))
        .tint(BikeGoGoStyle.brand)
        .accessibilityLabel("呼叫 \(name)")
    }
}

private struct VoiceAudioInfo: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(BikeGoGoStyle.brand)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct VoiceParticipantRow: View {
    let participant: VoiceParticipantSnapshot

    private var statusColor: Color {
        if participant.isSpeaking { return BikeGoGoStyle.route }
        if participant.connectionQuality.contains("较差")
            || participant.connectionQuality.contains("中断") {
            return BikeGoGoStyle.warning
        }
        return BikeGoGoStyle.brand
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "person.fill")
                    .foregroundStyle(statusColor)
                    .frame(width: 44, height: 44)
                    .background(statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: BikeGoGoStyle.cornerRadius))

                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color(uiColor: .secondarySystemGroupedBackground), lineWidth: 2))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(participant.isLocal ? "\(participant.displayName)（我）" : participant.displayName)
                    .font(.body.weight(.semibold))
                Text("\(participant.connectionQuality) · \(participant.audioStatus)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: participant.isMuted ? "mic.slash.fill" : "mic.fill")
                .foregroundStyle(participant.isMuted ? BikeGoGoStyle.warning : statusColor)
                .frame(width: 34, height: 34)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct VoiceEmptyState: View {
    let title: String
    let systemImage: String
    var actionTitle: String?
    var action: (() -> Void)?

    init(
        title: String,
        systemImage: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: BikeGoGoStyle.cornerRadius))
                    .tint(BikeGoGoStyle.brand)
            }
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: BikeGoGoStyle.cornerRadius))
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
    @EnvironmentObject private var appState: AppState
    @ObservedObject var account: AccountClient
    let groupID: String
    @State private var showingDeleteConfirmation = false

    private var group: AppGroup? {
        account.groups.first { $0.id == groupID }
    }

    var body: some View {
        List {
            if let group {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "person.3.fill")
                            .font(.title2)
                            .foregroundStyle(BikeGoGoStyle.brand)
                            .frame(width: 48, height: 48)
                            .background(BikeGoGoStyle.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: BikeGoGoStyle.cornerRadius))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(group.name)
                                .font(.headline)
                            Text("\(group.members.count) 位成员")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        Task { await appState.startVoiceCall(targetID: group.id) }
                    } label: {
                        Label("呼叫小队", systemImage: "phone.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: BikeGoGoStyle.cornerRadius))
                    .tint(BikeGoGoStyle.brand)
                    .disabled(appState.hasActiveVoiceCall || appState.isHandlingVoiceInvitation)
                }

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
