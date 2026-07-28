import AVFAudio
import AuthenticationServices
import CoreLocation
import CryptoKit
import HealthKit
import Security
import SwiftUI
import UIKit
import UserNotifications

struct FriendsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        AccountView(account: appState.accountClient)
    }
}

private struct AccountView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var account: AccountClient
    @State private var isAddingFriend = false
    @State private var isEditingProfile = false
    @State private var copiedFriendCode = false

    var body: some View {
        NavigationStack {
            List {
                if let user = account.currentUser {
                    profileSection(user)
                    accountSecuritySection(user)
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

                        if account.requiresAppleSignIn {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("这个设备上的账户已受 Apple ID 保护。")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                AppleSignInControl(account: account)
                            }
                        } else if !account.isWorking {
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

                    NavigationLink {
                        AccountSettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .disabled(account.currentUser == nil)
                    .accessibilityLabel("账户与隐私设置")
                }
            }
            .refreshable {
                await account.refresh()
            }
            .task {
                await account.refresh(presentsErrors: false)
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
                    Text(user.isAppleAccount ? "Apple 账户" : "访客账户")
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

    private func accountSecuritySection(_ user: AppUser) -> some View {
        Section("账户安全") {
            if user.isAppleAccount {
                Label("已连接 Apple ID", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.green)

                Button(role: .destructive) {
                    Task { await account.signOut() }
                } label: {
                    Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .disabled(account.isWorking)
            } else {
                Text("连接 Apple ID 后，可在更换或重装设备后恢复好友账户。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                AppleSignInControl(account: account)
            }
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

private struct AccountSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @State private var notificationStatus = "读取中"
    @State private var isExporting = false
    @State private var exportedFile: ExportedAccountFile?
    @State private var confirmsDeletion = false

    private var account: AccountClient {
        appState.accountClient
    }

    var body: some View {
        List {
            Section("账户") {
                if let user = account.currentUser {
                    LabeledContent("账户类型") {
                        Text(user.isAppleAccount ? "Apple 账户" : "访客账户")
                    }
                    LabeledContent("好友码") {
                        Text(user.friendCode)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }

            Section {
                Button {
                    exportData()
                } label: {
                    Label(
                        isExporting ? "正在生成数据文件" : "导出我的数据",
                        systemImage: "square.and.arrow.up"
                    )
                }
                .disabled(isExporting || account.isWorking)

                Link(destination: AppConfiguration.privacyPolicyURL) {
                    Label("隐私政策", systemImage: "hand.raised")
                }
            } header: {
                Text("数据与隐私")
            } footer: {
                Text("导出文件包含账户资料、好友关系、小队和已同步的骑行记录，不包含登录令牌或推送令牌。")
            }

            Section {
                PermissionStatusRow(
                    title: "定位",
                    systemImage: "location",
                    status: locationStatus
                )
                PermissionStatusRow(
                    title: "通知",
                    systemImage: "bell",
                    status: notificationStatus
                )
                PermissionStatusRow(
                    title: "麦克风",
                    systemImage: "mic",
                    status: microphoneStatus
                )
                PermissionStatusRow(
                    title: "健康与健身",
                    systemImage: "heart",
                    status: healthStatus
                )

                Button {
                    guard let url = URL(
                        string: UIApplication.openSettingsURLString
                    ) else { return }
                    UIApplication.shared.open(url)
                } label: {
                    Label("打开系统设置", systemImage: "gear")
                }
            } header: {
                Text("系统权限")
            } footer: {
                Text("权限由 iPhone 系统管理。定位和麦克风关闭后，路线记录或骑行语音将无法正常工作。")
            }

            Section {
                Button(role: .destructive) {
                    confirmsDeletion = true
                } label: {
                    Label("永久删除账户", systemImage: "person.crop.circle.badge.minus")
                }
                .disabled(!appState.canDeleteAccount || account.isWorking)
            } header: {
                Text("危险操作")
            } footer: {
                Text(deletionFooter)
            }
        }
        .navigationTitle("账户与隐私")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshNotificationStatus()
        }
        .sheet(item: $exportedFile) { file in
            ActivityView(activityItems: [file.url])
                .presentationDetents([.medium, .large])
        }
        .alert("永久删除账户？", isPresented: $confirmsDeletion) {
            Button("取消", role: .cancel) {}
            Button("永久删除", role: .destructive) {
                Task {
                    if await appState.deleteAccountAndLocalData() {
                        dismiss()
                    }
                }
            }
        } message: {
            Text("好友关系、小队、云端骑行记录和本机骑行数据都会被删除。此操作无法撤销。")
        }
    }

    private var deletionFooter: String {
        if !appState.canDeleteAccount {
            return "当前有尚未结束的骑行。请先结束或放弃骑行，再删除账户。"
        }
        return "删除后无法恢复。应用会建立一个不含旧数据的新访客账户。"
    }

    private var locationStatus: String {
        switch appState.locationAuthorizationStatus {
        case .authorizedAlways: return "始终允许"
        case .authorizedWhenInUse: return "使用期间"
        case .denied: return "已关闭"
        case .restricted: return "受限制"
        case .notDetermined: return "未请求"
        @unknown default: return "未知"
        }
    }

    private var microphoneStatus: String {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return "已允许"
        case .denied: return "已关闭"
        case .undetermined: return "未请求"
        @unknown default: return "未知"
        }
    }

    private var healthStatus: String {
        guard HKHealthStore.isHealthDataAvailable() else {
            return "设备不可用"
        }
        switch HKHealthStore().authorizationStatus(for: .workoutType()) {
        case .sharingAuthorized: return "已允许写入"
        case .sharingDenied: return "未允许写入"
        case .notDetermined: return "未请求"
        @unknown default: return "未知"
        }
    }

    private func exportData() {
        isExporting = true
        Task {
            defer { isExporting = false }
            if let url = await account.exportPersonalData() {
                exportedFile = ExportedAccountFile(url: url)
            }
        }
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current()
            .notificationSettings()
        switch settings.authorizationStatus {
        case .authorized: notificationStatus = "已允许"
        case .provisional: notificationStatus = "临时允许"
        case .ephemeral: notificationStatus = "临时会话"
        case .denied: notificationStatus = "已关闭"
        case .notDetermined: notificationStatus = "未请求"
        @unknown default: notificationStatus = "未知"
        }
    }
}

private struct PermissionStatusRow: View {
    let title: String
    let systemImage: String
    let status: String

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(status)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ExportedAccountFile: Identifiable {
    let url: URL

    var id: String {
        url.path
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(
        context: Context
    ) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

private struct AppleSignInControl: View {
    @ObservedObject var account: AccountClient
    @State private var rawNonce: String?

    var body: some View {
        SignInWithAppleButton(.continue) { request in
            do {
                let nonce = try Self.randomNonce()
                rawNonce = nonce
                request.requestedScopes = [.fullName, .email]
                request.nonce = Self.sha256(nonce)
            } catch {
                account.errorMessage = "无法准备 Apple 登录，请稍后重试。"
            }
        } onCompletion: { result in
            guard let rawNonce else {
                account.errorMessage = "Apple 登录请求已失效，请重新尝试。"
                return
            }

            switch result {
            case let .success(authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                      let tokenData = credential.identityToken,
                      let identityToken = String(data: tokenData, encoding: .utf8) else {
                    account.errorMessage = "没有收到有效的 Apple 身份信息。"
                    return
                }
                let displayName = credential.fullName.map {
                    PersonNameComponentsFormatter().string(from: $0)
                }?.trimmingCharacters(in: .whitespacesAndNewlines)
                Task {
                    _ = await account.signInWithApple(
                        identityToken: identityToken,
                        rawNonce: rawNonce,
                        displayName: displayName?.isEmpty == false ? displayName : nil
                    )
                }

            case let .failure(error):
                if (error as? ASAuthorizationError)?.code != .canceled {
                    account.errorMessage = "Apple 登录未完成：\(error.localizedDescription)"
                }
            }
            self.rawNonce = nil
        }
        .signInWithAppleButtonStyle(.black)
        .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
        .disabled(account.isWorking)
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func randomNonce(length: Int = 32) throws -> String {
        let characters = Array(
            "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._"
        )
        var result = ""
        var remaining = length

        while remaining > 0 {
            var bytes = [UInt8](repeating: 0, count: 16)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                throw AppleNonceError.randomGenerationFailed
            }
            for byte in bytes where byte < characters.count {
                result.append(characters[Int(byte)])
                remaining -= 1
                if remaining == 0 { break }
            }
        }
        return result
    }
}

private enum AppleNonceError: Error {
    case randomGenerationFailed
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
