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
APPLE_BUNDLE_ID=com.sssnto.BikeGoGo
APPLE_SIGN_IN_KEY_ID=<Sign in with Apple Key ID>
APPLE_SIGN_IN_TEAM_ID=FR9RTRV9BC
APPLE_SIGN_IN_CLIENT_ID=com.sssnto.BikeGoGo
APPLE_SIGN_IN_KEY_PATH=/run/secrets/apple-sign-in-key.p8
SESSION_TTL_DAYS=30
TRUST_PROXY_HOPS=1
POSTGRES_DB=bikegogogo
POSTGRES_USER=bikegogogo
POSTGRES_PASSWORD=<64位十六进制强密码>
APNS_KEY_ID=CM2W9J6CX3
APNS_TEAM_ID=FR9RTRV9BC
APNS_TOPIC=com.sssnto.BikeGoGo
APNS_ENVIRONMENT=sandbox
APNS_KEY_PATH=/run/secrets/AuthKey_CM2W9J6CX3.p8
APNS_PRODUCTION_KEY_ID=<Production Key ID，未准备时留空>
APNS_PRODUCTION_KEY_PATH=/run/secrets/apns-production-key.p8
```

注意：

- `LIVEKIT_API_SECRET` 只放在 NAS 的容器环境变量或 NAS 私有 env 文件里。
- 不要把真实密钥写进 GitHub 仓库。
- iOS App 不直接连接 LiveKit API Secret，只向这个后端请求短期 token。
- `APPLE_BUNDLE_ID` 必须与 iOS target 的 Product Bundle Identifier 完全一致。
- `TRUST_PROXY_HOPS=1` 表示后端前只有 Nginx Proxy Manager 一层可信代理。这样限流会按
  真实客户端 IP 分开计算，而不是让所有用户共用 NAS 代理 IP 的额度。不要填写大于实际
  代理层数的值，否则客户端可能伪造转发来源。若请求路径为
  `客户端 -> CDN -> Nginx Proxy Manager -> 后端`，填写 `2`。
- Apple 身份公钥由服务端从 Apple 官方 JWKS 自动读取。账户删除还需要后端调用 Apple
  Token 撤销接口，因此 NAS 必须另外保存启用了 **Sign in with Apple** 的私钥。
- `apple-sign-in-key.p8` 不等同于只启用了 APNs 的推送私钥。只有 Apple Developer
  后台明确为同一 Key 启用了 Sign in with Apple 时才能共用；建议使用独立 Key。
- PostgreSQL 不映射宿主机端口，只允许同一 Compose 网络中的后端访问。
- 配置 `DATABASE_URL` 后，PostgreSQL 是主存储；服务端会继续更新
  `/data/bikegogogo.json`，作为便于检查和紧急回滚的镜像。
- APNs `.p8` 通过只读文件挂载，不能写入 `.env` 或提交到 GitHub。

### 创建 Sign in with Apple 私钥

1. 登录 ，进入 **Certificates, Identifiers & Profiles**。
2. 在 **Identifiers** 中打开 `com.sssnto.BikeGoGo`，确认 **Sign in with Apple** 已启用，
   并配置为 Primary App ID。
3. 进入 **Keys**，点击 `+`，名称可填写 `BikeGoGo Sign in with Apple`。
4. 勾选 **Sign in with Apple**，点击 **Configure**，选择 BikeGoGo 的 Primary App ID。
5. 完成创建后记录 Key ID，并立即下载 `.p8`。Apple 私钥只能下载一次。
6. 在 NAS 的 `deploy/nas` 目录执行：

```bash
cp /你的下载目录/AuthKey_<KEY_ID>.p8 secrets/apple-sign-in-key.p8
chmod 600 secrets/apple-sign-in-key.p8
```

7. 在 `.env` 中填写：

```bash
APPLE_SIGN_IN_KEY_ID=<KEY_ID>
APPLE_SIGN_IN_TEAM_ID=FR9RTRV9BC
APPLE_SIGN_IN_CLIENT_ID=com.sssnto.BikeGoGo
```

原生 iOS App 使用 Bundle ID 作为 Client ID，不需要为这条原生删除流程新增网站 Services ID。
Team ID 可以在 Apple Developer 的 Membership Details 中查看。

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
  -e APPLE_BUNDLE_ID=com.sssnto.BikeGoGo \
  -e SESSION_TTL_DAYS=30 \
  -e TRUST_PROXY_HOPS=1 \
  -v bikegogogo-data:/data \
  ghcr.io/<你的 GitHub 用户名小写>/bikegogogo-server:latest
```

检查：

```bash
curl http://<NAS_IP>:8080/health
```

健康检查响应中的 `revision` 是当前镜像对应的 Git 提交 SHA。每个 HTTP 响应还会返回
`X-Request-ID`；排查客户端错误时，可以在 NAS 容器日志中搜索该值：

```bash
docker compose logs bikegogogo-server | grep '<X-Request-ID>'
```

## Docker Compose 部署

仓库已经提供 NAS Compose 模板：

```text
deploy/nas/docker-compose.yml
deploy/nas/.env.example
```

当前 Compose 同时部署业务 API、隐私政策、运营管理后台和 PostgreSQL。运营后台的
首次初始化、双因素认证及反向代理配置见
[运营管理后台部署](ADMIN_DEPLOYMENT.md)。

把 `deploy/nas` 目录复制到 NAS 后：

```bash
cp .env.example .env
```

先生成一个只包含十六进制字符的数据库密码，避免 URL 编码问题：

```bash
openssl rand -hex 32
```

然后把 `.env` 里的 `LIVEKIT_API_KEY`、`LIVEKIT_API_SECRET` 和
`POSTGRES_PASSWORD` 改成真实值，并把 APNs 私钥放到：

```text
deploy/nas/secrets/AuthKey_CM2W9J6CX3.p8
```

设置目录和文件权限：

```bash
mkdir -p secrets
chmod 700 secrets
chmod 600 secrets/AuthKey_CM2W9J6CX3.p8
```

`docker-compose.yml` 内容示例：

```yaml
services:
  bikegogogo-server:
    image: ghcr.io/sssnto/bikegogogo-server:latest
    container_name: bikegogogo-server
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
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
      DATABASE_URL: "postgresql://${POSTGRES_USER:-bikegogogo}:${POSTGRES_PASSWORD:?set POSTGRES_PASSWORD in deploy/nas/.env}@postgres:5432/${POSTGRES_DB:-bikegogogo}"
      APPLE_BUNDLE_ID: "com.sssnto.BikeGoGo"
      APPLE_SIGN_IN_KEY_ID: "${APPLE_SIGN_IN_KEY_ID}"
      APPLE_SIGN_IN_TEAM_ID: "${APPLE_SIGN_IN_TEAM_ID}"
      APPLE_SIGN_IN_CLIENT_ID: "${APPLE_SIGN_IN_CLIENT_ID}"
      APPLE_SIGN_IN_KEY_PATH: "/run/secrets/apple-sign-in-key.p8"
      SESSION_TTL_DAYS: "30"
      APNS_KEY_ID: "${APNS_KEY_ID}"
      APNS_TEAM_ID: "${APNS_TEAM_ID}"
      APNS_TOPIC: "${APNS_TOPIC}"
      APNS_ENVIRONMENT: "${APNS_ENVIRONMENT}"
      APNS_KEY_PATH: "/run/secrets/AuthKey_${APNS_KEY_ID}.p8"
      APNS_PRODUCTION_KEY_ID: "${APNS_PRODUCTION_KEY_ID:-}"
      APNS_PRODUCTION_KEY_PATH: "/run/secrets/apns-production-key.p8"
    volumes:
      - bikegogogo-data:/data
      - "./secrets:/run/secrets:ro"

  postgres:
    image: postgres:16-alpine
    container_name: bikegogogo-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: "${POSTGRES_DB:-bikegogogo}"
      POSTGRES_USER: "${POSTGRES_USER:-bikegogogo}"
      POSTGRES_PASSWORD: "${POSTGRES_PASSWORD:?set POSTGRES_PASSWORD in deploy/nas/.env}"
      POSTGRES_INITDB_ARGS: "--data-checksums"
      PGDATA: "/var/lib/postgresql/data/pgdata"
    volumes:
      - bikegogogo-postgres:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \"$${POSTGRES_USER}\" -d \"$${POSTGRES_DB}\""]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 20s

volumes:
  bikegogogo-data:
  bikegogogo-postgres:
```

同目录 `.env`：

```bash
LIVEKIT_API_KEY=your_livekit_api_key
LIVEKIT_API_SECRET=your_livekit_api_secret
APPLE_BUNDLE_ID=com.sssnto.BikeGoGo
APPLE_SIGN_IN_KEY_ID=<Sign in with Apple Key ID>
APPLE_SIGN_IN_TEAM_ID=FR9RTRV9BC
APPLE_SIGN_IN_CLIENT_ID=com.sssnto.BikeGoGo
SESSION_TTL_DAYS=30
POSTGRES_DB=bikegogogo
POSTGRES_USER=bikegogogo
POSTGRES_PASSWORD=<openssl rand -hex 32 的输出>
APNS_KEY_ID=CM2W9J6CX3
APNS_TEAM_ID=FR9RTRV9BC
APNS_TOPIC=com.sssnto.BikeGoGo
APNS_ENVIRONMENT=sandbox
```

启动：

```bash
docker compose up -d
docker compose ps
```

`bikegogogo-postgres` 应显示 `healthy`，`bikegogogo-server` 随后才会启动。

## 从 JSON 升级到 PostgreSQL

本版本会自动完成首次迁移，不需要手工导入 SQL：

1. PostgreSQL 中还没有 `bikegogogo_app_state` 数据时，服务端读取现有
   `/data/bikegogogo.json`。
2. 原文件复制为 `/data/bikegogogo.json.pre-postgresql.json`。这个文件只创建一次，
   后续启动不会覆盖。
3. 用户、会话、好友、小队、骑行和推送 token 整体写入 PostgreSQL。
4. 之后 PostgreSQL 成为唯一读取来源；每次成功写入数据库后同步更新 JSON 镜像。
5. 如果配置了 `DATABASE_URL` 但数据库不可用，服务端会启动失败，不会静默使用旧 JSON，
   避免两个数据源分别继续写入。

第一次升级前，先在 `deploy/nas` 目录创建独立备份：

```bash
mkdir -p backups
docker compose cp bikegogogo-server:/data/bikegogogo.json \
  "./backups/bikegogogo-before-postgresql-$(date +%Y%m%d-%H%M%S).json"
docker compose exec -T postgres sh -c \
  'pg_dump -Fc -U "$POSTGRES_USER" "$POSTGRES_DB"' \
  > "./backups/postgresql-before-upgrade-$(date +%Y%m%d-%H%M%S).dump"
```

然后升级：

```bash
docker compose pull
docker compose up -d --force-recreate
docker compose ps
docker compose logs --tail=100 bikegogogo-server
```

验收健康状态：

```bash
curl https://bikegogogo-server.sssnto.cn:8443/health
docker compose exec bikegogogo-server \
  ls -l /data/bikegogogo.json /data/bikegogogo.json.pre-postgresql.json
docker compose exec -T postgres sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
  "SELECT revision,
          jsonb_array_length(payload->'\''users'\'') AS users,
          jsonb_array_length(payload->'\''pushTokens'\'') AS push_tokens,
          updated_at
   FROM bikegogogo_app_state;"'
```

健康接口应返回 `"storage":"postgresql"`，数据库查询应至少保留你当前的 1 个 push
token。随后在 iPhone 上打开“我的”和“好友”，确认账户、好友码和已有数据正常，再编辑一次
昵称并重启容器，确认修改仍然存在。

### 日常备份

`bikegogogo-postgres` 现在是主数据卷，`bikegogogo-data` 是 JSON 镜像和导入前备份。
两个卷都必须备份。除 NAS 的卷快照外，建议每天执行一次逻辑备份：

```bash
docker compose exec -T postgres sh -c \
  'pg_dump -Fc -U "$POSTGRES_USER" "$POSTGRES_DB"' \
  > "./backups/postgresql-$(date +%Y%m%d-%H%M%S).dump"
docker compose cp bikegogogo-server:/data/bikegogogo.json \
  "./backups/bikegogogo-$(date +%Y%m%d-%H%M%S).json"
```

升级或重建容器时不要删除这两个卷，也不要执行 `docker compose down -v`。

### 紧急回滚到 JSON

如果新版本数据库路径出现问题：

1. 执行 `docker compose stop bikegogogo-server`。
2. 暂时从 `docker-compose.yml` 的服务端环境变量中删除 `DATABASE_URL`。
3. 执行 `docker compose up -d --force-recreate bikegogogo-server`。
4. `/health` 返回 `"storage":"json"` 后检查 iPhone 数据。

服务端会使用最后一次成功写入后的 JSON 镜像。不要删除 PostgreSQL 卷；排查完成后恢复
`DATABASE_URL` 并重新启动，即可重新使用数据库中的主数据。


## 对外暴露的服务

需要由 NAS 向反向代理提供三个内网 HTTP 服务：

```text
BikeGoGo API：容器 8080/tcp，NAS 默认映射 8080/tcp
隐私政策：容器 80/tcp，NAS 默认映射 8081/tcp
运营后台：容器 8082/tcp，NAS 默认映射 8082/tcp
公网访问：只通过反向代理提供 HTTPS
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
- PostgreSQL。
- 未来的 Redis。
- LiveKit API Secret。

BikeGoGo 运营后台可以通过独立域名经 HTTPS 反向代理开放给管理员，但不要直接暴露
NAS 的 `8082` 端口。后台自带密码、TOTP 双因素认证、会话超时、CSRF 防护和审计日志，
仍建议在 Nginx Proxy Manager 上增加来源 IP 白名单或 VPN 限制。

LiveKit Cloud 本身不需要你在 NAS 上暴露端口。客户端会拿到后端签发的 token，再连接 `wss://bikegogo-qy7s1sfz.livekit.cloud`。

## 隐私政策服务与 Nginx Proxy Manager

隐私政策镜像为 `ghcr.io/sssnto/bikegogogo-privacy:latest`。镜像构建时使用 Pandoc 将
`docs/PRIVACY_POLICY.md` 和 `docs/SUPPORT.md` 转为适合手机浏览的静态 HTML，运行时只包含 Nginx，不连接
PostgreSQL，也不接收或保存用户数据。

首次部署前，先把本次代码合并到 `main`，等待 GitHub Actions 中的
`Build Production Docker Images` 成功。该工作流会发布支持 AMD64 和 ARM64 的
`bikegogogo-privacy:latest`。也可以在 Actions 页面手动运行该工作流；只有 `main`
分支构建会更新 `latest` 标签。

若 GHCR Package 尚未设为 Public，需要先在 NAS 登录。密码应使用有 `read:packages`
权限的 GitHub Personal Access Token，不要使用 GitHub 登录密码：

```bash
docker login ghcr.io -u sssnto
```

在 NAS 的 `.env` 中保留或修改隐私服务端口：

```dotenv
BIKEGOGOGO_PRIVACY_PORT=8081
```

更新并启动服务：

```bash
docker compose pull privacy-policy
docker compose up -d privacy-policy
curl http://127.0.0.1:8081/health
curl -I http://127.0.0.1:8081/
```

第一个命令应返回 `ok`，第二个命令应返回 `200`，并包含 `Content-Security-Policy`、
`X-Content-Type-Options` 和 `X-Frame-Options` 响应头。

在 Nginx Proxy Manager 中选择 `Hosts > Proxy Hosts > Add Proxy Host`：

| 配置项 | 填写内容 |
| --- | --- |
| Domain Names | `bikegogogo-privacy.sssnto.cn` |
| Scheme | `http` |
| Forward Hostname / IP | NAS 的局域网 IP |
| Forward Port | `8081`，或 `.env` 中修改后的端口 |
| Cache Assets | 关闭 |
| Block Common Exploits | 开启 |
| Websockets Support | 关闭 |

在 `SSL` 页签申请新的 Let's Encrypt 证书，开启 `Force SSL`、`HTTP/2 Support` 和
`HSTS Enabled`。路由器无需把 `8081` 直接映射到公网；公网只开放 Nginx Proxy Manager
使用的 HTTPS 端口。

完成后验证：

```bash
curl https://bikegogogo-privacy.sssnto.cn/health
curl -I https://bikegogogo-privacy.sssnto.cn/
curl -I https://bikegogogo-privacy.sssnto.cn/support/
```

然后在 App Store Connect 的“App 隐私 > 隐私政策 URL”填写：

```text
https://bikegogogo-privacy.sssnto.cn
```

iOS App 内的隐私政策入口也已使用该地址。若最终使用其他域名，必须同时修改两份
`Support/Info.plist` 中的 `BikeGoGoPrivacyPolicyURL` 后重新 Archive。

## 当前 HTTP 接口

### 健康检查

```http
GET /health
```

响应：

```json
{
  "ok": true,
  "service": "bikegogogo-server",
  "storage": "postgresql"
}
```

用途：

- NAS 容器健康检查。
- 反向代理探活。
- GitHub Actions 或后续监控探活。

### 访客账户和好友

```http
POST  /v1/auth/guest
POST  /v1/auth/apple
DELETE /v1/session
GET   /v1/me
PATCH /v1/me
GET   /v1/me/export
DELETE /v1/me
GET   /v1/friends
GET   /v1/friends/requests
POST  /v1/friends/requests
POST  /v1/friends/requests/{requestId}/accept
POST  /v1/friends/requests/{requestId}/reject
GET   /v1/groups
POST  /v1/groups
POST  /v1/groups/{groupId}/members
DELETE /v1/groups/{groupId}/members/{userId}
DELETE /v1/groups/{groupId}
GET   /v1/groups/{groupId}/live-locations
PUT   /v1/groups/{groupId}/live-location
DELETE /v1/groups/{groupId}/live-location
POST  /v1/groups/{groupId}/sos
PUT   /v1/devices/push-token
DELETE /v1/devices/push-token
GET   /v1/voice/invitations
POST  /v1/voice/invitations
POST  /v1/voice/invitations/{invitationId}/respond
DELETE /v1/voice/invitations/{invitationId}
POST  /v1/voice/rooms/{friendUserId 或 groupId}/token
GET   /v1/rides
GET   /v1/rides/{rideId}
PUT   /v1/rides/{rideId}
DELETE /v1/rides/{rideId}
```

除 `POST /v1/auth/guest` 和 `POST /v1/auth/apple` 外，这些接口都要求
`Authorization: Bearer <accessToken>`。完整请求示例见 `docs/API_DESIGN.md`。

### 账户导出与永久删除部署说明

这两个接口复用 PostgreSQL、现有 Bearer 鉴权和 HTTPS 反向代理，不增加环境变量、
中间件、数据卷或公网端口。更新客户端前需要先更新 NAS 镜像：

```bash
docker compose pull bikegogogo-server
docker compose up -d --force-recreate bikegogogo-server
docker compose logs --tail=100 bikegogogo-server
curl https://bikegogogo-server.sssnto.cn:8443/health
```

`GET /v1/me/export` 不返回设备摘要、会话令牌或推送 token。`DELETE /v1/me` 要求请求体
中的 `confirmation` 精确为 `DELETE`，每个来源每小时最多调用 3 次。删除在一次数据库
原子更新中完成；成功后旧 Bearer token 立即失效。生产环境执行删除测试前应先确认
PostgreSQL 和 JSON 镜像备份均可恢复。

### 小队实时位置部署说明

小队实时位置共享复用现有 HTTPS 后端和账户鉴权，不需要新增环境变量、中间件、数据卷
或公网端口。升级镜像后按普通流程重建服务端即可：

```bash
docker compose pull bikegogogo-server
docker compose up -d --force-recreate bikegogogo-server
docker compose logs --tail=100 bikegogogo-server
curl https://bikegogogo-server.sssnto.cn:8443/health
```

实时位置仅在后端进程内存中保留 90 秒，容器重启会立即清空，这是预期的隐私保护行为。
当前 NAS 应只运行一个 `bikegogogo-server` 实例；如果未来要横向扩展为多个实例，需要先
用 Redis 等共享的短期存储替换进程内存，否则不同实例查询到的位置可能不一致。

SOS 复用相同的临时位置存储和现有 APNs Sandbox/Production 配置，不需要新增环境变量。
升级本次后端镜像后，`POST /v1/groups/{groupId}/sos` 会向其他成员发送普通 alert 推送。
容器只需主动访问 Apple APNs 的 `443`，不增加公网入站端口。接口每 10 分钟最多调用
3 次，且仅允许当前小队成员使用。

### 获取 LiveKit 语音房间 Token

客户端会先通过 `/v1/voice/invitations` 创建好友或小队邀请。后端使用现有 APNs
production/sandbox 配置发送来电提醒，不需要新增容器或公网端口。邀请有效期为 90 秒；
接听或拒绝使用 `POST /v1/voice/invitations/{invitationId}/respond`，发起方结束时使用
`DELETE /v1/voice/invitations/{invitationId}`。

```http
POST /v1/voice/rooms/{friendUserId 或 groupId}/token
Content-Type: application/json
Authorization: Bearer <accessToken>
```

请求：

```json
{
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

- 后端从账户会话读取语音身份和昵称，客户端不能指定其他用户身份。
- 好友房间要求双方已接受好友关系；小队房间要求当前账号是成员，否则返回 `403`。
- 无 Authorization 或会话过期时返回 `401`。
- 全局限制每个来源每分钟 120 个请求，登录接口每分钟 10 次，语音令牌每分钟 30 次。
- 服务端对好友组合或小队 ID 做 SHA-256，生成稳定且不可直接推导的 LiveKit room。

## 公网安全边界

- 公网只开放反向代理的 HTTPS 端口；容器的 `8080`、`8081`、`8082` 只在 NAS 内网使用。
- HTTPS/TLS 加密客户端到 NAS 的请求，包括 Bearer token 和业务数据。
- 服务端仅保存访问令牌、设备 ID 的 SHA-256 摘要；iOS 原始令牌存入 Keychain。
- LiveKit API Secret 只留在 NAS，iOS 获得的是 2 小时有效的房间 JWT。
- `GET /health` 保持公开，其余业务接口按上述规则鉴权。
- PostgreSQL 和 JSON 镜像都包含路线、账号、会话和推送 token，应纳入 NAS 加密备份；
  不要把数据卷暴露为网络共享。
- APNs 只需要容器主动访问 Apple 的 TCP `443`，不新增任何公网入站端口。
- 小队实时位置只保留 90 秒且不进入数据库；服务端仍会校验 Bearer token 和小队成员关系。
- 小队 SOS 坐标沿用 90 秒临时位置，不进入数据库，并限制为每 10 分钟最多 3 次。
- 当前数据库状态使用 PostgreSQL 的事务与版本号保护，但仍是单行 JSONB 模型，适合小规模
  TestFlight 内测；扩大用户量前再按用户、关系和骑行记录拆分为规范化数据表。

## 反向代理建议

如果 NAS 支持反向代理，建议：

- 外部 443 HTTPS。
- 反向代理到容器 `http://127.0.0.1:8080` 或 `http://<NAS_IP>:8080`。
- 开启自动 HTTPS 证书。
- 开启 TLS 1.2/1.3，并把 HTTP 请求重定向到 HTTPS。
- 建议添加 `Strict-Transport-Security: max-age=31536000`。
- 限制只转发 `/health` 和 `/v1/` 路径。

示例转发：

```text
https://bikegogogo-server.sssnto.cn:8443/health -> http://127.0.0.1:8080/health
https://bikegogogo-server.sssnto.cn:8443/v1/*  -> http://127.0.0.1:8080/v1/*
```

运营后台应使用不同域名，例如：

```text
https://bikegogogo-admin.sssnto.cn/* -> http://127.0.0.1:8082/*
```

后台域名必须启用 HTTPS，不要与客户端 API 共用路径或 Cookie 域。
