# BikeGoGo Server

这个目录是 BikeGoGo 后端服务。当前已提供访客账户、好友关系和 LiveKit token，
后续继续补 Apple 登录、小队和骑行云同步。

- 设备绑定的访客账户和用户资料。
- 好友申请、同意、拒绝和好友列表。
- LiveKit room token 签发。
- 骑行记录与轨迹点同步。
- APNs 推送。

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
- JSON 文件持久化，MVP 部署到 Docker 数据卷。
- PostgreSQL，下一阶段接入。
- Redis，语音在线状态和同步阶段接入。

## 已实现 API

```http
GET /health
POST /v1/auth/guest
GET /v1/me
PATCH /v1/me
GET /v1/friends
GET /v1/friends/requests
POST /v1/friends/requests
POST /v1/friends/requests/:requestId/accept
POST /v1/friends/requests/:requestId/reject
POST /v1/voice/rooms/:groupId/token
```

注意：LiveKit API Secret 只能放在后端，不能放进 iOS App。

## Docker

本地构建：

```bash
docker build -t bikegogogo-server .
```

运行：

```bash
docker run --rm -p 8080:8080 --env-file .env \
  -v bikegogogo-data:/data bikegogogo-server
```

GitHub Actions 会把镜像推送到 GitHub Container Registry。NAS 部署步骤见 `docs/NAS_DOCKER_DEPLOYMENT.md`。
