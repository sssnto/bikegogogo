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

当前状态：Sandbox 与 Production 双通道代码、普通社交通知链路已完成，等待
TestFlight 和双真机验收。

当前配置：

- Sandbox APNs `.p8` Key。
- Key ID `CM2W9J6CX3`。
- Team ID `FR9RTRV9BC`。

TestFlight 前还需要创建 Production APNs Key，在 NAS 配置
`APNS_PRODUCTION_KEY_ID` 和 `secrets/apns-production-key.p8`。Sandbox 与 Production
会同时运行，不需要切换 NAS 的 `APNS_ENVIRONMENT`。

`.p8` 私钥不要粘贴到聊天或提交到 Git，应通过 NAS secret 文件或受保护环境变量挂载。
完整操作见 [APNs 私钥申请与保管](APNS_SETUP.md)。

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

建议优先级：扩大内测前必须。当前版本已由 PostgreSQL 16 接管主存储，首次启动会自动
导入 NAS Docker 数据卷中的旧 JSON，并继续写入 JSON 镜像用于备份和紧急回滚。

NAS Compose 已包含 PostgreSQL 16 容器、健康检查和独立数据卷，并且没有映射数据库
端口。后端容器可通过下面的内部地址访问：

```text
DATABASE_URL=postgresql://bikegogogo:<强密码>@postgres:5432/bikegogogo
```

目前使用带事务和版本冲突检测的单行 JSONB 状态，适合小规模 TestFlight 内测。扩大
用户量后再按用户、好友关系、小队、骑行和轨迹点拆分为规范化数据表。

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

下一开发批次请提前准备：

- PostgreSQL 16。
- APNs `.p8` Key、Key ID 和 Team ID。

Redis 和对象存储当前不阻塞。`.p8` 私钥不要发送到聊天中，后续部署时通过 NAS secret
文件只读挂载；PostgreSQL 只加入 Docker 内部网络，不开放公网端口。
