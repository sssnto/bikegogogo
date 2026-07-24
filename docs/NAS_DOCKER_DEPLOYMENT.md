# NAS Docker 部署说明

这份文档用于把 BikeGoGo 后端通过 GitHub Actions 打包成 Docker 镜像，再部署到家里的 NAS。

## 镜像发布

GitHub Actions 工作流：

```text
.github/workflows/server-docker.yml
```

触发方式：

- 推送到 `main`，且变更包含 `server/**` 或工作流文件。
- 推送 `v*` tag，例如 `v0.1.0`。
- 在 GitHub Actions 页面手动运行 `workflow_dispatch`。

镜像仓库：

```text
ghcr.io/<你的 GitHub 用户名小写>/bikegogogo-server
```

常用 tag：

- `latest`：默认分支最新镜像。
- `main`：main 分支镜像。
- `sha-xxxxxxx`：具体提交镜像。
- `v0.1.0`：版本 tag 镜像。

如果 GitHub Container Registry 包是 private，NAS 拉取镜像前需要登录：

```bash
docker login ghcr.io
```

用户名填 GitHub 用户名，密码填有 `read:packages` 权限的 GitHub Personal Access Token。

## NAS 上的环境变量

容器必须配置：

```bash
PORT=8080
LIVEKIT_URL=wss://bikegogo-qy7s1sfz.livekit.cloud
LIVEKIT_API_KEY=your_livekit_api_key
LIVEKIT_API_SECRET=your_livekit_api_secret
ALLOWED_ORIGINS=
DATA_FILE=/data/bikegogogo.json
```

注意：

- `LIVEKIT_API_SECRET` 只放在 NAS 的容器环境变量或 NAS 私有 env 文件里。
- 不要把真实密钥写进 GitHub 仓库。
- iOS App 不直接连接 LiveKit API Secret，只向这个后端请求短期 token。

## Docker Run 部署

```bash
docker pull ghcr.io/<你的 GitHub 用户名小写>/bikegogogo-server:latest

docker run -d \
  --name bikegogogo-server \
  --restart unless-stopped \
  -p 8080:8080 \
  -e PORT=8080 \
  -e LIVEKIT_URL=wss://bikegogo-qy7s1sfz.livekit.cloud \
  -e LIVEKIT_API_KEY=your_livekit_api_key \
  -e LIVEKIT_API_SECRET=your_livekit_api_secret \
  -e ALLOWED_ORIGINS= \
  -e DATA_FILE=/data/bikegogogo.json \
  -v bikegogogo-data:/data \
  ghcr.io/<你的 GitHub 用户名小写>/bikegogogo-server:latest
```

检查：

```bash
curl http://<NAS_IP>:8080/health
```

## Docker Compose 部署

仓库已经提供 NAS Compose 模板：

```text
deploy/nas/docker-compose.yml
deploy/nas/.env.example
```

把 `deploy/nas` 目录复制到 NAS 后：

```bash
cp .env.example .env
```

然后把 `.env` 里的 `LIVEKIT_API_KEY` 和 `LIVEKIT_API_SECRET` 改成你的真实值。

`docker-compose.yml` 内容示例：

```yaml
services:
  bikegogogo-server:
    image: ghcr.io/sssnto/bikegogogo-server:latest
    container_name: bikegogogo-server
    restart: unless-stopped
    ports:
      - "${BIKEGOGOGO_HTTP_PORT:-8080}:8080"
    environment:
      NODE_ENV: "production"
      PORT: "8080"
      LIVEKIT_URL: "wss://bikegogo-qy7s1sfz.livekit.cloud"
      LIVEKIT_API_KEY: "${LIVEKIT_API_KEY}"
      LIVEKIT_API_SECRET: "${LIVEKIT_API_SECRET}"
      ALLOWED_ORIGINS: ""
      DATA_FILE: "/data/bikegogogo.json"
    volumes:
      - bikegogogo-data:/data

volumes:
  bikegogogo-data:
```

同目录 `.env`：

```bash
LIVEKIT_API_KEY=your_livekit_api_key
LIVEKIT_API_SECRET=your_livekit_api_secret
```

启动：

```bash
docker compose up -d
```

升级：

```bash
docker compose pull
docker compose up -d --force-recreate
```

`bikegogogo-data` 是用户资料、好友申请和好友关系的数据卷。升级或重建容器时不要删除
这个卷，也不要执行 `docker compose down -v`。备份可通过 NAS 的 Docker 卷备份功能，
或暂停容器后备份卷内的 `bikegogogo.json`。

## 对外暴露的服务

当前只需要暴露 BikeGoGo 后端 HTTP 服务：

```text
容器端口：8080/tcp
NAS 映射端口：建议 8080/tcp
公网访问：建议通过反向代理提供 HTTPS
```

当前公网地址：

```text
https://bikegogogo-server.sssnto.cn:8443
```

iOS App 的 `BikeGoGoAPIBaseURL` 配置为：

```text
https://bikegogogo-server.sssnto.cn:8443
```

不要对公网暴露：

- NAS 管理后台。
- Docker daemon。
- 未来的 PostgreSQL。
- 未来的 Redis。
- LiveKit API Secret。

LiveKit Cloud 本身不需要你在 NAS 上暴露端口。客户端会拿到后端签发的 token，再连接 `wss://bikegogo-qy7s1sfz.livekit.cloud`。

## 当前 HTTP 接口

### 健康检查

```http
GET /health
```

响应：

```json
{
  "ok": true,
  "service": "bikegogogo-server"
}
```

用途：

- NAS 容器健康检查。
- 反向代理探活。
- GitHub Actions 或后续监控探活。

### 访客账户和好友

```http
POST  /v1/auth/guest
GET   /v1/me
PATCH /v1/me
GET   /v1/friends
GET   /v1/friends/requests
POST  /v1/friends/requests
POST  /v1/friends/requests/{requestId}/accept
POST  /v1/friends/requests/{requestId}/reject
```

除 `POST /v1/auth/guest` 外，这些接口都要求
`Authorization: Bearer <accessToken>`。完整请求示例见 `docs/API_DESIGN.md`。

### 获取 LiveKit 语音房间 Token

```http
POST /v1/voice/rooms/{groupId}/token
Content-Type: application/json
Authorization: Bearer <accessToken>
```

请求：

```json
{
  "identity": "user_123",
  "displayName": "Peng",
  "canPublish": true,
  "canSubscribe": true
}
```

响应：

```json
{
  "url": "wss://bikegogo-qy7s1sfz.livekit.cloud",
  "token": "livekit_jwt",
  "roomName": "group-weekend"
}
```

当前 MVP 注意事项：

- 新版 iOS 使用访客账户鉴权，后端从会话读取语音身份。
- 为兼容旧版 iOS，无 Authorization 时仍可在请求体传 `identity` 和 `displayName`。
- 生产公网暴露前建议加 HTTPS、限流、鉴权和日志脱敏。
- `groupId` 会映射为 LiveKit room：`group-{groupId}`。

## 反向代理建议

如果 NAS 支持反向代理，建议：

- 外部 443 HTTPS。
- 反向代理到容器 `http://127.0.0.1:8080` 或 `http://<NAS_IP>:8080`。
- 开启自动 HTTPS 证书。
- 限制只转发 `/health` 和 `/v1/` 路径。

示例转发：

```text
https://bikegogogo-server.sssnto.cn:8443/health -> http://127.0.0.1:8080/health
https://bikegogogo-server.sssnto.cn:8443/v1/*  -> http://127.0.0.1:8080/v1/*
```
