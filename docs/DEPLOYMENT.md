# BikeGoGo 部署文档

## 1. 准备 Apple 开发环境

1. 安装 Xcode 26.3 或更新版本。
2. 登录 Apple Developer Program。
3. 在 Xcode 的 Settings > Accounts 中添加 Apple ID。
4. 准备一台 iPhone 真机和一块 Apple Watch 真机。HealthKit、后台定位、WatchConnectivity 的很多行为必须真机测试。

当前开发团队 ID 为 `FR9RTRV9BC`，Apple Developer Program 已通过审核。

在 [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list)
确认两个 App ID：

```text
com.sssnto.BikeGoGo
com.sssnto.BikeGoGo.watchkitapp
```

iOS App ID 开启 `Sign in with Apple`、`HealthKit` 和 `Push Notifications`；Watch App ID
开启 `HealthKit`。修改 capability 后回到 Xcode，让 Automatic Signing 重新生成
provisioning profile。

## 2. 打开现有 Xcode 工程

仓库已经包含真正的 iOS 和 watchOS target，不需要再次创建工程：

```bash
open BikeGoGo/BikeGoGo.xcodeproj
```

首次打开后：

1. 等待顶部状态栏中的 Swift Package 解析结束。
2. 在 Project Navigator 选择蓝色的 `BikeGoGo` 项目。
3. iPhone target 是 `BikeGoGo`，Bundle ID 是 `com.sssnto.BikeGoGo`。
4. Watch target 是 `BikeGoGoWatch`，Bundle ID 是 `com.sssnto.BikeGoGo.watchkitapp`。
5. 两个 target 的 Team 都检查为你的 Apple Developer Team。
6. 模拟器先选择 `BikeGoGo` scheme 和一台 iPhone，按 `Cmd+R`。
7. Watch 模拟器选择 `BikeGoGoWatch` scheme 和一组配对的 Apple Watch，按 `Cmd+R`。

工程会自动把 `BikeGoGoWatch.app` 嵌入 iPhone App 的 `Watch` 目录。LiveKit 通过 Swift Package Manager 管理，版本锁定文件位于 Xcode workspace 的 `xcshareddata/swiftpm`。

## 3. iPhone 真机

iOS App target 使用：

- Background Modes
  - Location updates
  - Audio, AirPlay, and Picture in Picture
  - Remote notifications
- HealthKit。
- Sign in with Apple。
- Push Notifications（APNs 接入前先开启 capability）。

Info.plist 需要配置：

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>BikeGoGo 需要定位来记录你的骑行路线。</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>BikeGoGo 需要后台定位，以便锁屏后继续记录骑行路线。</string>
<key>NSMicrophoneUsageDescription</key>
<string>BikeGoGo 需要麦克风用于骑行小队实时语音。</string>
<key>NSHealthShareUsageDescription</key>
<string>BikeGoGo 需要读取心率和运动数据来展示骑行统计。</string>
<key>NSHealthUpdateUsageDescription</key>
<string>BikeGoGo 需要写入骑行记录到 Apple 健康。</string>
<key>NSBluetoothAlwaysUsageDescription</key>
<string>BikeGoGo 后续可连接踏频、功率等骑行蓝牙设备。</string>
```

仓库已经提供模板：

- `Apps/iOS/BikeGoGo/Support/Info.plist`
- `Apps/iOS/BikeGoGo/Support/BikeGoGo.entitlements`

在 Xcode target 的 Build Settings 中检查：

- `Info.plist File` 指向 iOS 模板。
- `Code Signing Entitlements` 指向 iOS entitlements 模板。
- 真机联调公网后端时，`BikeGoGoAPIBaseURL` 使用 `https://bikegogogo-server.sssnto.cn:8443`。
- 如果临时联调 Mac 本地后端，再把 `BikeGoGoAPIBaseURL` 改成 Mac 的局域网 IP，例如 `http://192.168.1.23:8080`。

第一次连接 iPhone：

1. 用数据线或同一 Wi-Fi 连接 iPhone，手机上开启 Developer Mode。
2. Xcode 顶部设备菜单选择这台 iPhone。
3. 在 `BikeGoGo > Signing & Capabilities` 确认没有红色签名错误。
4. 按 `Cmd+R` 安装。
5. 第一次开始骑行时先允许“使用 App 时定位”，随后允许“始终定位”。
6. 第一次加入语音时允许麦克风。
7. 在“我的 > 账户安全”点击“通过 Apple 继续”，确认访客好友码在绑定后不变。
8. 骑行开始后锁屏 3 至 5 分钟，再解锁确认路线和计时继续增长。

## 4. Apple Watch 真机

Watch App target 需要开启：

- HealthKit。
- Background Modes > Workout processing。
- 如果 Watch 端播放语音或提示音，再开启 Audio。

Watch target 已配置 HealthKit 使用说明、`workout-processing` 后台模式和 companion Bundle ID。

仓库已经提供模板：

- `Apps/watchOS/BikeGoGoWatch/Support/Info.plist`
- `Apps/watchOS/BikeGoGoWatch/Support/BikeGoGoWatch.entitlements`

真机运行：

1. 确认 Apple Watch 已与测试 iPhone 配对，并在 Watch App 中开启开发者模式。
2. Xcode 选择 `BikeGoGoWatch` scheme。
3. 设备选择与该 iPhone 配对的 Apple Watch。
4. 在 `BikeGoGoWatch > Signing & Capabilities` 确认 Team 正确。
5. 按 `Cmd+R`，首次启动允许读写 HealthKit。
6. 保持 Watch App 在后台，从 iPhone 点击“开始骑行”。
7. 确认 Watch 被自动唤醒，并开始类型为“户外单车”的 workout。
8. 确认 iPhone 收到 Watch 心率；从任意一端暂停、继续和结束，另一端同步。
9. 结束后在 iPhone 的“健康/健身记录”中确认 outdoor cycling workout 已保存。

若没有自动唤醒，依次检查：

- iPhone 与 Watch 已配对且 Watch App 已安装。
- 两个 target 使用同一 Team，Bundle ID 与 companion 配置一致。
- iPhone 和 Watch 都已允许 BikeGoGo 访问健康数据。
- Watch 未开启低电量模式，且系统版本为 watchOS 10 或更高。

## 5. LiveKit

MVP 推荐先用 LiveKit Cloud：

1. 创建 LiveKit Cloud 项目。
2. 获取 `LIVEKIT_URL`、`LIVEKIT_API_KEY`、`LIVEKIT_API_SECRET`。
3. 后端保存这些变量。
4. iOS App 只请求后端 token，不保存 secret。

仓库已经提供后端 token endpoint：

```bash
cd server
cp .env.example .env
npm install
npm run dev
```

填写 `.env`：

```bash
LIVEKIT_URL=wss://your-project.livekit.cloud
LIVEKIT_API_KEY=your_key
LIVEKIT_API_SECRET=your_secret
```

真实密钥只放在 `server/.env`。这个文件已经被 `.gitignore` 排除，不要提交到 Git。

验证：

```bash
LOGIN_JSON=$(curl -sS -X POST http://localhost:8080/v1/auth/guest \
  -H "Content-Type: application/json" \
  -d '{"deviceId":"local-device-identifier","displayName":"本地骑友"}')

ACCESS_TOKEN=$(printf '%s' "$LOGIN_JSON" | jq -r .accessToken)

# FRIEND_USER_ID 必须是已经互相同意的好友用户 ID。
curl -X POST "http://localhost:8080/v1/voice/rooms/$FRIEND_USER_ID/token" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"canPublish":true,"canSubscribe":true}'
```

当前 App 已指向公网服务 `https://bikegogogo-server.sssnto.cn:8443`。两台 iPhone 使用固定
演示小队房间，LiveKit identity 由后端账户决定，因此可以直接进行双机测试：

1. 两台 iPhone 都安装当前版本。
2. 两边打开“语音”页并点击“加入语音”。
3. 确认成员列表出现两名成员。
4. 分别测试静音、锁屏、切后台。
5. 通话中切换 Wi-Fi 和蜂窝网络，界面应短暂显示“正在重连”后恢复。

后端环境变量示例：

```bash
LIVEKIT_URL=wss://your-project.livekit.cloud
LIVEKIT_API_KEY=your_key
LIVEKIT_API_SECRET=your_secret
APPLE_BUNDLE_ID=com.sssnto.BikeGoGo
SESSION_TTL_DAYS=30
```

完整外部服务准备清单见 [中间件准备清单](MIDDLEWARE_PREP.md)。

## 6. 后端部署建议

小规模内测可以使用：

- Fly.io / Render / Railway 部署 API。
- Supabase / Neon 托管 PostgreSQL。
- Upstash 托管 Redis。
- LiveKit Cloud 托管语音。

生产化后再考虑自建 LiveKit。

如果你使用家里的 NAS 部署后端，优先走 Docker 镜像：

- GitHub Actions 自动构建并推送 GHCR 镜像。
- NAS 拉取镜像后通过 Docker 或 Docker Compose 运行。
- 详细步骤见 [NAS Docker 部署](NAS_DOCKER_DEPLOYMENT.md)。

## 7. TestFlight

1. Xcode 选择 Any iOS Device。
2. Product > Archive。
3. Organizer 中选择 Distribute App。
4. 选择 App Store Connect。
5. 上传后在 App Store Connect 创建 TestFlight 测试。
6. 邀请好友邮箱加入测试。

首次上传前还需要：

1. 在 App Store Connect 创建 Bundle ID 为 `com.sssnto.BikeGoGo` 的 App。
2. 为 Build 设置递增的 `CURRENT_PROJECT_VERSION`。
3. 完成出口合规问答；当前 HTTPS/LiveKit 使用系统标准加密，通常选择不使用自定义加密。
4. 内部测试员可直接邀请；外部测试员需要先通过 TestFlight Beta App Review。

## 8. App Store 审核注意事项

审核材料必须解释：

- 为什么需要后台定位：用于骑行时锁屏继续记录路线。
- 为什么需要麦克风：用于好友小队实时语音。
- 为什么需要 HealthKit：读取心率并写入 workout。
- 如何保护隐私：好友必须双方同意，位置默认不公开。

建议提供一个演示账号和一段说明，告诉审核人员如何开始一条骑行和进入语音房间。
