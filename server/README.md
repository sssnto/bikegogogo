# BikeGoGo Server

这个目录是 BikeGoGo 后端服务。当前已提供访客账户、Sign in with Apple、好友关系、
小队、骑行云同步、APNs 推送和受账户鉴权保护的 LiveKit token。

- 设备绑定的访客账户和用户资料。
- Apple JWT 验证、访客账户绑定和会话退出。
- 好友申请、同意、拒绝和好友列表。
- 小队创建、邀请、移出、退出和解散。
- 需要登录且校验好友/小队成员关系的 LiveKit room token 签发。
- 骑行记录、指标和轨迹点同步。
- PostgreSQL 16 主存储及旧 JSON 自动迁移、镜像备份。
- APNs Sandbox/Production 双通道，按 App 构建环境隔离 device token。

## 本地启动

复制环境变量：

```bash
cp .env.example .env
```

填写 LiveKit Cloud 项目的：

```bash
LIVEKIT_URL=wss://your-project.livekit.cloud
LIVEKIT_API_KEY=your_key
LIVEKIT_API_SECRET=your_secret
APPLE_BUNDLE_ID=com.sssnto.BikeGoGo
SESSION_TTL_DAYS=30
```

`server/.env` 已被 `.gitignore` 排除，不要把真实 API Secret 写入 `.env.example`、README 或任何会提交到 Git 的文件。

安装依赖并启动：

```bash
npm install
npm run dev
```

健康检查：

```bash
curl http://localhost:8080/health
```

创建访客账户：

```bash
curl -X POST http://localhost:8080/v1/auth/guest \
  -H "Content-Type: application/json" \
  -d '{"deviceId":"local-device-identifier","displayName":"本地骑友"}'
```

响应中的 `accessToken` 用于后续请求的
`Authorization: Bearer <accessToken>`。完整接口示例见 `docs/API_DESIGN.md`。

## 技术栈

- Node.js + TypeScript。
- Fastify。
- LiveKit Server SDK。
- PostgreSQL 16 主存储。
- JSON 滚动镜像和迁移前备份。
- APNs HTTP/2 token 鉴权推送。

## 已实现 API

```http
GET /health
POST /v1/auth/guest
POST /v1/auth/apple
DELETE /v1/session
PUT /v1/push-tokens
DELETE /v1/push-tokens/:token
GET /v1/me
PATCH /v1/me
GET /v1/friends
GET /v1/friends/requests
POST /v1/friends/requests
POST /v1/friends/requests/:requestId/accept
POST /v1/friends/requests/:requestId/reject
GET /v1/groups
POST /v1/groups
POST /v1/groups/:groupId/members
DELETE /v1/groups/:groupId/members/:userId
DELETE /v1/groups/:groupId
POST /v1/voice/rooms/:groupId/token
GET /v1/rides
GET /v1/rides/:rideId
PUT /v1/rides/:rideId
DELETE /v1/rides/:rideId
```

注意：LiveKit API Secret 只能放在后端，不能放进 iOS App。

## Docker

本地构建：

```bash
docker build -t bikegogogo-server server
```

运行：

```bash
docker run --rm -p 8080:8080 --env-file server/.env \
  -v bikegogogo-data:/data bikegogogo-server
```

GitHub Actions 会把镜像推送到 GitHub Container Registry。NAS 部署步骤见 `docs/NAS_DOCKER_DEPLOYMENT.md`。
