# BikeGoGo Server

这个目录是 BikeGoGo 后端服务骨架。当前已提供 LiveKit token endpoint，后续继续补用户、好友、小队和骑行云同步。

- Apple 登录后的用户会话。
- 好友申请和小队管理。
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

获取语音房间 token：

```bash
curl -X POST http://localhost:8080/v1/voice/rooms/weekend/token \
  -H "Content-Type: application/json" \
  -d '{"identity":"local-user","displayName":"Peng"}'
```

## 技术栈

- Node.js + TypeScript。
- Fastify。
- LiveKit Server SDK。
- PostgreSQL，下一阶段接入。
- Redis，语音在线状态和同步阶段接入。

## 已实现 API

```http
GET /health
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
docker run --rm -p 8080:8080 --env-file .env bikegogogo-server
```

GitHub Actions 会把镜像推送到 GitHub Container Registry。NAS 部署步骤见 `docs/NAS_DOCKER_DEPLOYMENT.md`。
