# BikeGoGo 部署文档

## 1. 准备 Apple 开发环境

1. 安装 Xcode 26.3 或更新版本。
2. 登录 Apple Developer Program。
3. 在 Xcode 的 Settings > Accounts 中添加 Apple ID。
4. 准备一台 iPhone 真机和一块 Apple Watch 真机。HealthKit、后台定位、WatchConnectivity 的很多行为必须真机测试。

如果 Apple Developer Program 账号仍在审核中：

- 可以先创建 Xcode 工程、整理源码、跑 Swift 包测试。
- 可以先启动本地后端并验证 LiveKit token endpoint。
- 可能无法完整开启 HealthKit、Push Notifications、TestFlight 和部分真机签名能力。
- 审核通过后，第一时间在 Apple Developer 后台确认 Bundle ID、Capabilities 和证书。

## 2. 创建 Xcode 工程

当前仓库已经准备好源码目录。第一次创建 Xcode 工程时：

1. 打开 Xcode。
2. File > New > Project。
3. 选择 iOS App。
4. Product Name 填 `BikeGoGo`。
5. Interface 选 SwiftUI。
6. Language 选 Swift。
7. Bundle Identifier 建议使用：`com.yourname.bikegogogo`。
8. 保存位置选择本仓库根目录。
9. 创建后添加 watchOS App target：File > New > Target > watchOS App。

然后把这些源码加入 target：

- `Apps/iOS/BikeGoGo` 加入 iOS App target。
- `Apps/watchOS/BikeGoGoWatch` 加入 Watch App target。
- `Sources/BikeGoGoCore` 作为本地 Swift Package 被两个 target 依赖。

## 3. iOS Capabilities

iOS App target 需要开启：

- Background Modes
  - Location updates
  - Audio, AirPlay, and Picture in Picture
  - Remote notifications
- HealthKit
- Push Notifications
- Sign in with Apple，账号功能阶段开启。

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

## 4. watchOS Capabilities

Watch App target 需要开启：

- HealthKit。
- Background Modes > Workout processing。
- 如果 Watch 端播放语音或提示音，再开启 Audio。

Watch extension 的 Info 也要配置 HealthKit 使用说明。

仓库已经提供模板：

- `Apps/watchOS/BikeGoGoWatch/Support/Info.plist`
- `Apps/watchOS/BikeGoGoWatch/Support/BikeGoGoWatch.entitlements`

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
curl -X POST http://localhost:8080/v1/voice/rooms/weekend/token \
  -H "Content-Type: application/json" \
  -d '{"identity":"local-user","displayName":"Peng"}'
```

后端环境变量示例：

```bash
LIVEKIT_URL=wss://your-project.livekit.cloud
LIVEKIT_API_KEY=your_key
LIVEKIT_API_SECRET=your_secret
DATABASE_URL=postgres://user:password@host:5432/bikegogogo
REDIS_URL=redis://host:6379
APNS_KEY_ID=key_id
APNS_TEAM_ID=team_id
APNS_BUNDLE_ID=com.yourname.bikegogogo
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

## 8. App Store 审核注意事项

审核材料必须解释：

- 为什么需要后台定位：用于骑行时锁屏继续记录路线。
- 为什么需要麦克风：用于好友小队实时语音。
- 为什么需要 HealthKit：读取心率并写入 workout。
- 如何保护隐私：好友必须双方同意，位置默认不公开。

建议提供一个演示账号和一段说明，告诉审核人员如何开始一条骑行和进入语音房间。
