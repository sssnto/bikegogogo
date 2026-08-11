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
            ScrollView {
                if let user = account.currentUser {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        profileCard(user)
                        relationshipSummary
                        requestsSection
                        friendsSection
                        pendingSection
                        statusSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                } else {
                    unavailableAccount
                        .padding(.horizontal, 16)
                        .padding(.top, 80)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("我的")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
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

    private func profileCard(_ user: AppUser) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                ProfileAvatar(name: user.displayName, size: 60)

                VStack(alignment: .leading, spacing: 4) {
                    Text(user.displayName)
                        .font(.title3.bold())
                        .lineLimit(1)
                    Text(user.isAppleAccount ? "Apple 账户" : "访客账户")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    isEditingProfile = true
                } label: {
                    Image(systemName: "pencil")
                        .frame(width: 36, height: 36)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: BikeGoGoStyle.cornerRadius))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("修改昵称")
            }

            Divider()

            Button {
                UIPasteboard.general.string = user.friendCode
                copiedFriendCode = true
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    copiedFriendCode = false
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("好友码")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(user.friendCode)
                            .font(.system(.body, design: .monospaced, weight: .semibold))
                    }

                    Spacer(minLength: 12)

                    Text(copiedFriendCode ? "已复制" : "复制")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(copiedFriendCode ? BikeGoGoStyle.route : BikeGoGoStyle.brand)
                    Image(systemName: copiedFriendCode ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(copiedFriendCode ? BikeGoGoStyle.route : BikeGoGoStyle.brand)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: BikeGoGoStyle.cornerRadius))
    }

    private var relationshipSummary: some View {
        HStack(spacing: 0) {
            relationshipMetric(
                value: account.friends.count,
                title: "好友",
                systemImage: "person.2.fill"
            )
            Divider().frame(height: 42)
            relationshipMetric(
                value: account.groups.count,
                title: "小队",
                systemImage: "person.3.fill"
            )
            Divider().frame(height: 42)
            relationshipMetric(
                value: account.incomingRequests.count,
                title: "待处理",
                systemImage: "person.crop.circle.badge.clock"
            )
        }
        .padding(.vertical, 14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: BikeGoGoStyle.cornerRadius))
    }

    private func relationshipMetric(
        value: Int,
        title: String,
        systemImage: String
    ) -> some View {
        VStack(spacing: 5) {
            Label("\(value)", systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(BikeGoGoStyle.brand)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var requestsSection: some View {
        if !account.incomingRequests.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                AccountSectionHeader(
                    title: "好友申请",
                    value: "\(account.incomingRequests.count) 个待处理"
                )

                ForEach(account.incomingRequests) { request in
                    VStack(spacing: 14) {
                        PersonLabel(
                            user: request.user,
                            subtitle: "希望添加你为骑行好友"
                        )

                        HStack(spacing: 10) {
                            Button {
                                Task { await account.respond(to: request.id, accept: false) }
                            } label: {
                                Label("忽略", systemImage: "xmark")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .buttonBorderShape(.roundedRectangle(radius: BikeGoGoStyle.cornerRadius))
                            .tint(.secondary)

                            Button {
                                Task { await account.respond(to: request.id, accept: true) }
                            } label: {
                                Label("同意", systemImage: "checkmark")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .buttonBorderShape(.roundedRectangle(radius: BikeGoGoStyle.cornerRadius))
                            .tint(BikeGoGoStyle.brand)
                        }
                    }
                    .padding(14)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: BikeGoGoStyle.cornerRadius))
                }
            }
        }
    }

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AccountSectionHeader(title: "骑行好友", value: "\(account.friends.count) 人")

            if account.friends.isEmpty {
                Button {
                    isAddingFriend = true
                } label: {
                    Label("添加第一位好友", systemImage: "person.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .buttonBorderShape(.roundedRectangle(radius: BikeGoGoStyle.cornerRadius))
                .tint(BikeGoGoStyle.brand)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(account.friends.enumerated()), id: \.element.id) { index, friend in
                        PersonLabel(user: friend, subtitle: "可发起好友语音")
                            .padding(14)

                        if index < account.friends.count - 1 {
                            Divider().padding(.leading, 64)
                        }
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: BikeGoGoStyle.cornerRadius))
            }
        }
    }

    @ViewBuilder
    private var pendingSection: some View {
        if !account.outgoingRequests.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                AccountSectionHeader(title: "已发送申请", value: "\(account.outgoingRequests.count) 个")

                VStack(spacing: 0) {
                    ForEach(Array(account.outgoingRequests.enumerated()), id: \.element.id) { index, request in
                        HStack(spacing: 12) {
                            PersonLabel(user: request.user)
                            Text("等待同意")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BikeGoGoStyle.warning)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(BikeGoGoStyle.warning.opacity(0.12), in: Capsule())
                        }
                        .padding(14)

                        if index < account.outgoingRequests.count - 1 {
                            Divider().padding(.leading, 64)
                        }
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: BikeGoGoStyle.cornerRadius))
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if let statusMessage = account.statusMessage {
            Label(statusMessage, systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(BikeGoGoStyle.route)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(BikeGoGoStyle.route.opacity(0.10), in: RoundedRectangle(cornerRadius: BikeGoGoStyle.cornerRadius))
        }
    }

    private var unavailableAccount: some View {
        VStack(spacing: 18) {
            if account.isWorking {
                ProgressView()
                    .controlSize(.large)
                Text("正在建立骑行账户")
                    .font(.headline)
            } else {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: 42))
                    .foregroundStyle(.secondary)
                Text("账户暂时不可用")
                    .font(.headline)

                if account.requiresAppleSignIn {
                    AppleSignInControl(account: account)
                } else {
                    Button {
                        Task {
                            await account.bootstrap(defaultDisplayName: "骑行好友")
                        }
                    } label: {
                        Label("重新连接", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .buttonBorderShape(.roundedRectangle(radius: BikeGoGoStyle.cornerRadius))
                    .tint(BikeGoGoStyle.brand)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: BikeGoGoStyle.cornerRadius))
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
                    HStack(spacing: 12) {
                        ProfileAvatar(name: user.displayName, size: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(user.displayName)
                                .font(.body.weight(.semibold))
                            Text(user.isAppleAccount ? "Apple 账户" : "访客账户")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    LabeledContent("好友码") {
                        Text(user.friendCode)
                            .font(.system(.body, design: .monospaced))
                    }

                    if user.isAppleAccount {
                        Label("已连接 Apple ID", systemImage: "checkmark.shield.fill")
                            .foregroundStyle(BikeGoGoStyle.route)

                        Button(role: .destructive) {
                            Task { await account.signOut() }
                        } label: {
                            Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        .disabled(account.isWorking)
                    } else {
                        AppleSignInControl(account: account)
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
                Text("权限由 iPhone 系统管理。")
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

    private var tint: Color {
        switch status {
        case "始终允许", "使用期间", "已允许", "已允许写入", "临时允许", "临时会话":
            BikeGoGoStyle.route
        case "已关闭", "未允许写入", "受限制", "设备不可用":
            BikeGoGoStyle.danger
        default:
            BikeGoGoStyle.warning
        }
    }

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(status)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(tint.opacity(0.12), in: Capsule())
        }
    }
}

private struct AccountSectionHeader: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ProfileAvatar: View {
    let name: String
    let size: CGFloat

    private var initial: String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }

    var body: some View {
        Text(initial.isEmpty ? "骑" : initial)
            .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(BikeGoGoStyle.brand, in: RoundedRectangle(cornerRadius: BikeGoGoStyle.cornerRadius))
            .accessibilityHidden(true)
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
    let subtitle: String?

    init(user: AppUser, subtitle: String? = nil) {
        self.user = user
        self.subtitle = subtitle
    }

    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatar(name: user.displayName, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(user.displayName)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
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
