# 外部中间件准备清单

这份清单按开发阶段排序。Apple Developer Program 和 LiveKit Cloud 已准备完成；接下来
真正需要提前准备的是云同步数据库和推送密钥。

## 现在就可以准备

### Apple Developer Program

用途：

- iPhone 真机调试。
- Apple Watch 真机调试。
- HealthKit。
- 后台定位。
- Push Notifications。
- TestFlight。

状态：已通过审核。

准备项：

- Apple Developer 账号。
- 一个明确的 Bundle ID，例如 `com.yourname.bikegogogo`。
- 一台 iPhone 真机。
- 一块 Apple Watch 真机。

当前 Bundle ID：

```text
com.sssnto.BikeGoGo
com.sssnto.BikeGoGo.watchkitapp
```

需要在 Apple Developer 后台为对应 App ID 开启：

- Sign in with Apple（iOS）。
- HealthKit（iOS、watchOS）。
- Push Notifications（iOS，接 APNs 时启用）。

## 第四阶段前准备

### LiveKit

用途：

- 小队实时语音。
- WebRTC 房间。
- 断线重连。
- 成员静音/说话状态。

建议优先级：语音 MVP 必须。

推荐路径：

1. 先用 LiveKit Cloud。
2. 内测稳定后再评估是否自建 LiveKit。

需要准备：

```bash
LIVEKIT_URL=wss://your-project.livekit.cloud
LIVEKIT_API_KEY=your_key
LIVEKIT_API_SECRET=your_secret
```

iOS App 不保存 `LIVEKIT_API_SECRET`，只能通过后端换取短期 room token。

当前仓库已准备：

- `server/src/index.ts`：LiveKit token endpoint。
- `server/.env.example`：LiveKit 环境变量模板。
- `Apps/iOS/BikeGoGo/Services/VoiceTokenService.swift`：iOS 请求 token 的客户端。

你需要保存好的信息：

- LiveKit 项目的 WebSocket URL。
- API Key。
- API Secret。

API Secret 只填到 `server/.env`，不要写进 iOS App。

### APNs

用途：

- 好友申请通知。
- 小队语音邀请。
- 后续 VoIP 语音提醒。

建议优先级：内测前必须。

下一步需要你准备：

- 一个 APNs `.p8` Key。
- Key ID。
- Team ID `FR9RTRV9BC`。

`.p8` 私钥不要粘贴到聊天或提交到 Git，应通过 NAS secret 文件或受保护环境变量挂载。

注意：

- VoIP PushKit 审核比较严格，必须配合 CallKit 并用于真实通话场景。
- 第一版可以先用普通推送通知，等语音通话体验稳定后再接 VoIP。

## 第五阶段前准备

### PostgreSQL

用途：

- 用户。
- 好友关系。
- 小队。
- 骑行记录。
- 轨迹点索引。

建议优先级：云同步必须。

你使用 NAS 时，推荐直接准备 PostgreSQL 16 容器，并只开放 Docker 内部网络。后续需要：

```text
DATABASE_URL=postgresql://bikegogogo:<强密码>@postgres:5432/bikegogogo
```

也可以使用托管服务：

- Supabase。
- Neon。
- Railway PostgreSQL。

### Redis

用途：

- 在线状态。
- 小队语音临时状态。
- 短期 token 缓存。
- 任务限流。

建议优先级：多人语音和云同步阶段建议准备。

推荐托管：

- Upstash。
- Railway Redis。

### 对象存储

用途：

- 头像。
- GPX/FIT 导出文件备份。
- 后续骑行照片。

建议优先级：可以延后。

推荐：

- Cloudflare R2。
- AWS S3。
- Supabase Storage。

## 可以暂时不准备

### 地图服务

第一版使用 Apple MapKit，不需要额外地图服务。

### 蓝牙骑行传感器平台

第一版先不接踏频、功率计、码表。后续可通过 Core Bluetooth 直接接 BLE 传感器。

### Strava

第一版先本地记录和 GPX 导出，Strava 同步可以后置。

## 建议的最小外部组合

下一开发批次的最小组合：

- PostgreSQL 16。
- APNs Key。

Redis 和对象存储当前不阻塞；骑行记录继续保存在手机本地，直到 PostgreSQL 云同步完成。
