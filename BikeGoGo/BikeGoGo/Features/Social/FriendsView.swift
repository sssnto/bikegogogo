import SwiftUI
import UIKit

struct FriendsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        AccountView(account: appState.accountClient)
    }
}

private struct AccountView: View {
    @ObservedObject var account: AccountClient
    @State private var isAddingFriend = false
    @State private var isEditingProfile = false
    @State private var copiedFriendCode = false

    var body: some View {
        NavigationStack {
            List {
                if let user = account.currentUser {
                    profileSection(user)
                    requestsSections
                    friendsSection
                    pendingSection
                    statusSection
                } else {
                    Section {
                        HStack(spacing: 12) {
                            if account.isWorking {
                                ProgressView()
                            } else {
                                Image(systemName: "wifi.exclamationmark")
                                    .foregroundStyle(.secondary)
                            }
                            Text(account.isWorking ? "正在建立骑行账户..." : "账户暂时不可用")
                                .foregroundStyle(.secondary)
                        }

                        if !account.isWorking {
                            Button {
                                Task {
                                    await account.bootstrap(defaultDisplayName: "骑行好友")
                                }
                            } label: {
                                Label("重新连接", systemImage: "arrow.clockwise")
                            }
                        }
                    }
                }
            }
            .navigationTitle("我的")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task { await account.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(account.currentUser == nil || account.isWorking)
                    .accessibilityLabel("刷新")

                    Button {
                        isAddingFriend = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                    .disabled(account.currentUser == nil || account.isWorking)
                    .accessibilityLabel("添加好友")
                }
            }
            .refreshable {
                await account.refresh()
            }
            .overlay {
                if account.isWorking, account.currentUser != nil {
                    ProgressView()
                        .padding(14)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .sheet(isPresented: $isAddingFriend) {
                AddFriendSheet(account: account)
            }
            .sheet(isPresented: $isEditingProfile) {
                EditProfileSheet(account: account)
            }
            .alert(
                "账户操作失败",
                isPresented: Binding(
                    get: { account.errorMessage != nil },
                    set: { if !$0 { account.errorMessage = nil } }
                )
            ) {
                Button("知道了") {
                    account.errorMessage = nil
                }
            } message: {
                Text(account.errorMessage ?? "")
            }
        }
    }

    private func profileSection(_ user: AppUser) -> some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 4) {
                    Text(user.displayName)
                        .font(.headline)
                    Text("访客账户")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    isEditingProfile = true
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("修改昵称")
            }

            Button {
                UIPasteboard.general.string = user.friendCode
                copiedFriendCode = true
            } label: {
                HStack {
                    Label("我的好友码", systemImage: "number")
                    Spacer()
                    Text(user.friendCode)
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                    Image(systemName: copiedFriendCode ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(copiedFriendCode ? .green : .secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var requestsSections: some View {
        if !account.incomingRequests.isEmpty {
            Section("待处理申请") {
                ForEach(account.incomingRequests) { request in
                    HStack(spacing: 12) {
                        PersonLabel(user: request.user)
                        Spacer()
                        Button {
                            Task { await account.respond(to: request.id, accept: false) }
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .tint(.secondary)
                        .accessibilityLabel("拒绝 \(request.user.displayName)")

                        Button {
                            Task { await account.respond(to: request.id, accept: true) }
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .tint(.green)
                        .accessibilityLabel("接受 \(request.user.displayName)")
                    }
                }
            }
        }
    }

    private var friendsSection: some View {
        Section("好友 \(account.friends.count)") {
            if account.friends.isEmpty {
                Text("还没有好友，使用右上角按钮输入对方的好友码。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(account.friends) { friend in
                    PersonLabel(user: friend)
                }
            }
        }
    }

    @ViewBuilder
    private var pendingSection: some View {
        if !account.outgoingRequests.isEmpty {
            Section("已发送") {
                ForEach(account.outgoingRequests) { request in
                    HStack {
                        PersonLabel(user: request.user)
                        Spacer()
                        Text("等待同意")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if let statusMessage = account.statusMessage {
            Section {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }
}

private struct PersonLabel: View {
    let user: AppUser

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.circle.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(user.displayName)
                .lineLimit(1)
        }
    }
}

private struct AddFriendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var account: AccountClient
    @State private var friendCode = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("8 位好友码", text: $friendCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: friendCode) { _, newValue in
                            friendCode = String(
                                newValue
                                    .uppercased()
                                    .filter { $0.isLetter || $0.isNumber }
                                    .prefix(8)
                            )
                        }
                } footer: {
                    Text("对方同意后，你们才会成为好友。")
                }
            }
            .navigationTitle("添加好友")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("发送") {
                        Task {
                            if await account.sendFriendRequest(friendCode: friendCode) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(friendCode.count != 8 || account.isWorking)
                }
            }
        }
    }
}

private struct EditProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var account: AccountClient
    @State private var displayName = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("骑行昵称", text: $displayName)
                    .onChange(of: displayName) { _, newValue in
                        displayName = String(newValue.prefix(30))
                    }
            }
            .navigationTitle("修改昵称")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                displayName = account.currentUser?.displayName ?? ""
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            if await account.updateDisplayName(
                                displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                            ) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(
                        displayName.trimmingCharacters(in: .whitespacesAndNewlines).count < 2
                        || account.isWorking
                    )
                }
            }
        }
    }
}
