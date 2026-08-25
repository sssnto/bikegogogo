# BikeGoGo 运营后台部署

运营后台由独立镜像 `ghcr.io/sssnto/bikegogogo-admin:latest` 提供，默认监听
`8082/tcp`。它只读取现有业务状态并写入独立的运营事件、管理员会话和审计表，不会向页面
返回 Apple subject、邮箱、APNs token、原始轨迹或健康明细。

## 1. 首次生成管理员资料

在可信电脑的仓库目录执行：

```bash
cd admin
npm install
npm run bootstrap -- admin '替换为至少16位的独立强密码'
```

命令会输出：

- `ADMIN_INITIAL_USERNAME`
- `ADMIN_INITIAL_PASSWORD_HASH`
- `ADMIN_INITIAL_TOTP_SECRET`
- 可导入 Apple 密码、1Password、Microsoft Authenticator 等应用的 `TOTP_URI`

密码哈希中包含 `$`。复制到 `deploy/nas/.env` 时必须使用单引号包裹整段哈希。TOTP
密钥和 URI 不要提交到 Git，也不要发送到聊天或截图中。

再生成两个互不相同的服务器密钥：

```bash
openssl rand -hex 32
openssl rand -hex 32
```

分别填入：

```dotenv
ANALYTICS_HMAC_SECRET=第一段64位十六进制值
ADMIN_ENCRYPTION_SECRET=第二段64位十六进制值
```

`ADMIN_ENCRYPTION_SECRET` 用于加密数据库中的 TOTP 密钥，部署后必须持续备份并保持不变。
`ANALYTICS_HMAC_SECRET` 用于把运营事件中的用户 ID 转换为不可逆的稳定标识；它不是客户端
请求签名密钥，也不能与管理员加密密钥复用。

## 2. NAS 启动

更新 `deploy/nas/docker-compose.yml` 和 `.env` 后运行：

```bash
docker compose pull
docker compose up -d
docker compose ps
curl http://127.0.0.1:8082/health
```

健康响应应包含：

```json
{"ok":true,"service":"bikegogogo-admin"}
```

首次登录成功并确认管理员已创建后，可以把 `.env` 中以下三项清空，再重新创建后台容器：

```dotenv
ADMIN_INITIAL_USERNAME=
ADMIN_INITIAL_PASSWORD_HASH=
ADMIN_INITIAL_TOTP_SECRET=
```

数据库中的管理员不会被删除，后续登录不受影响。保留
`ADMIN_ENCRYPTION_SECRET` 和 `ANALYTICS_HMAC_SECRET`。

## 3. Nginx Proxy Manager

建议使用独立域名，例如 `bikegogogo-admin.sssnto.cn`：

| 配置项 | 值 |
| --- | --- |
| Scheme | `http` |
| Forward Hostname / IP | NAS 局域网 IP |
| Forward Port | `8082` |
| Cache Assets | 关闭 |
| Block Common Exploits | 开启 |
| Websockets Support | 关闭 |
| SSL Certificate | 为后台域名单独申请 |
| Force SSL | 开启 |
| HTTP/2 Support | 开启 |
| HSTS | 开启 |

后台登录 Cookie 强制使用 `Secure`，因此正式环境必须通过 HTTPS 访问。建议再为 Proxy Host
添加 Nginx Proxy Manager 的 Access List，只允许管理员账户或可信来源；不要把 PostgreSQL
端口映射到公网。

## 4. 登录与页面

1. 打开后台 HTTPS 域名。
2. 输入管理员用户名和密码。
3. 输入认证器生成的 6 位动态验证码。
4. 查看运营总览、骑行运营、好友与小队、应用质量、用户支持和审计日志。

后台会话闲置 30 分钟失效，最长 8 小时；连续 5 次密码失败会锁定 15 分钟。用户支持页
只提供最小化摘要，所有用户搜索和详情访问均写入审计日志。

## 5. 数据口径与上线后的数据积累

- 当前业务存量来自 `bikegogogo_app_state`，上线后即可看到用户、骑行、好友、小队和推送
  token 的聚合统计。
- API 延迟、错误与 APNs 结果写入 `analytics_events`，从新服务端镜像部署后开始积累，历史
  日志不会自动补录。
- 客户端体验事件入口为认证后的 `POST /v1/telemetry/events`，当前服务端已准备好批量接收
  能力；iOS 精细漏斗将在后续版本逐项接入。
- `analytics_events` 自动保留 90 天，管理员审计日志自动保留 1 年；清理在后台服务启动时
  执行，不会删除业务骑行记录。
- Apple 下载量、商店展示量、崩溃和留存仍以 App Store Connect 为准，第一阶段不会猜测或
  用注册量代替这些数据。

## 6. 日常维护

```bash
docker compose logs --tail=200 bikegogogo-admin
docker compose restart bikegogogo-admin
docker compose pull bikegogogo-admin bikegogogo-server
docker compose up -d bikegogogo-admin bikegogogo-server
```

需要备份 PostgreSQL 中的业务状态以及 `admin_users`、`admin_audit_logs`、
`analytics_events`。若法规或内部制度要求更长留存周期，应先归档再启动新版本；不要手工把
审计日志与普通运营事件混在一起清理。
