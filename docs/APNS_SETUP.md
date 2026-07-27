# BikeGoGo APNs `.p8` 操作指南

## 1. `.p8` 是什么

APNs 是 Apple Push Notification service。BikeGoGo 后端需要向 APNs 证明“这条推送确实
来自你的开发者团队”，`.p8` 就是用于签署这个证明的私钥文件。

创建 APNs Key 后会得到三项配置：

```text
APNS_KEY_ID=Apple 生成的 10 位 Key ID
APNS_TEAM_ID=FR9RTRV9BC
APNS_KEY_PATH=/run/secrets/apns-private-key.p8
```

推送主题 `APNS_TOPIC` 是 iOS Bundle ID：

```text
com.sssnto.BikeGoGo
```

`.p8` 只放在后端/NAS，绝不能放进 iPhone App、聊天、GitHub 仓库或公开网盘。Apple
只允许下载一次；丢失后不能重新下载，只能撤销旧 Key 并创建新 Key。

## 2. 先确认 Push Notifications 能力

1. 登录 [Apple Developer](https://developer.apple.com/account/resources/identifiers/list)。
2. 打开 `Certificates, Identifiers & Profiles > Identifiers`。
3. 选择 `com.sssnto.BikeGoGo`，点击 `Edit`。
4. 勾选 `Push Notifications`，点击 `Save` 并确认。
5. 回到 Xcode，选择 `BikeGoGo` target。
6. 打开 `Signing & Capabilities`，确认存在 `Push Notifications`。
7. 重新选择 Team 或点击 `Try Again`，让 Automatic Signing 更新 provisioning profile。

修改 App ID capability 后，旧 provisioning profile 可能失效，需要让 Xcode 重新生成。
Watch App 暂时不需要单独创建推送 Key；第一版通知先送到 iPhone App。

## 3. 创建 APNs Key

创建 Key 需要 Apple Developer 账号的 `Account Holder` 或 `Admin` 权限。个人开发者账号
通常由账号本人操作。

1. 打开 [Certificates, Identifiers & Profiles > Keys](https://developer.apple.com/account/resources/authkeys/list)。
2. 点击左上角 `+`。
3. `Key Name` 填写容易识别的名称，例如：

   ```text
   BikeGoGo APNs Sandbox
   ```

4. 勾选 `Apple Push Notification service (APNs)`。
5. 如果右侧出现 `Configure`，点击它。
6. 真机从 Xcode 安装测试时选择 `Sandbox`/`Development` 环境。
7. 如果页面要求选择 Key 类型，BikeGoGo 只有一个 iOS App，推荐选择
   `Topic Specific`，然后勾选 `com.sssnto.BikeGoGo`。若页面只提供
   `Team Scoped`，也可以使用，但它对团队内其他 App 的权限更大。
8. 点击 `Continue`，检查环境与 Bundle ID。
9. 点击 `Confirm`。
10. 在结果页先记录 `Key ID`，然后点击 `Download`。

下载文件通常叫：

```text
AuthKey_ABCDEFGHIJ.p8
```

其中 `ABCDEFGHIJ` 就是 Key ID。下载完成前不要关闭页面。

### Sandbox 与 Production

- Xcode 直接安装的 Debug App 使用 APNs Sandbox。
- TestFlight 和 App Store App 使用 APNs Production。
- 如果 Apple 当前的 Key 创建页面要求选择环境，应再创建一个 Production Key，例如
  `BikeGoGo APNs Production`。
- 如果已有旧式 APNs Key 明确标注同时支持 Development 和 Production，则可以复用，
  但后端仍必须根据 App 构建来源选择正确的 APNs 主机。

后续开发初期先准备 Sandbox Key；准备 TestFlight 前再补 Production Key，可以减少误用。

## 4. 记录 Key ID 和 Team ID

Key ID：

1. 在 Developer Portal 的 `Keys` 列表点击刚创建的 Key。
2. 记录详情页中的 10 位 `Key ID`。

Team ID 已确认是：

```text
FR9RTRV9BC
```

这两个 ID 可以保存在 NAS `.env`，但 `.p8` 文件本身使用只读 secret 文件挂载。

## 5. 把 `.p8` 安全放到 NAS

在 NAS 创建一个不对外共享的目录。路径根据 NAS 品牌调整，例如：

```bash
mkdir -p /volume1/docker/bikegogogo/secrets
chmod 700 /volume1/docker/bikegogogo/secrets
```

通过 NAS 文件管理器或 `scp` 上传：

```text
AuthKey_ABCDEFGHIJ.p8
```

上传后：

```bash
chmod 600 /volume1/docker/bikegogogo/secrets/AuthKey_ABCDEFGHIJ.p8
```

要求：

- 不要放在 Git 仓库目录。
- 不要让该目录成为 SMB/AFP 公共共享目录。
- NAS 备份应加密。
- 不要把私钥内容复制进 `.env`，多行私钥容易损坏，也更容易泄漏。

## 6. 后续 Compose 挂载方式

后端 APNs 模块完成后，会在 Compose 中加入类似配置：

```yaml
services:
  bikegogogo-server:
    environment:
      APNS_KEY_ID: "${APNS_KEY_ID}"
      APNS_TEAM_ID: "${APNS_TEAM_ID}"
      APNS_TOPIC: "${APNS_TOPIC:-com.sssnto.BikeGoGo}"
      APNS_ENVIRONMENT: "${APNS_ENVIRONMENT:-sandbox}"
      APNS_KEY_PATH: "/run/secrets/apns-private-key.p8"
    volumes:
      - "./secrets/AuthKey_${APNS_KEY_ID}.p8:/run/secrets/apns-private-key.p8:ro"
```

`.env` 只写非私钥配置：

```bash
APNS_KEY_ID=ABCDEFGHIJ
APNS_TEAM_ID=FR9RTRV9BC
APNS_TOPIC=com.sssnto.BikeGoGo
APNS_ENVIRONMENT=sandbox
```

仓库已忽略 `*.p8` 和 `deploy/nas/secrets/`，但仍要在提交前执行 `git status` 检查。

## 7. 后端实际如何使用

后端使用 `.p8` 和 ES256 算法生成短期 JWT：

- JWT header：`alg=ES256`、`kid=APNS_KEY_ID`。
- JWT claims：`iss=APNS_TEAM_ID`、`iat=当前 UTC 时间`。
- JWT 最长只能使用一小时，服务端应定期刷新。
- 请求头 `apns-topic` 使用 `com.sssnto.BikeGoGo`。
- Sandbox 主机：`api.sandbox.push.apple.com:443`。
- Production 主机：`api.push.apple.com:443`。

NAS 只需允许容器主动访问外网 TCP `443`，不需要为 APNs 增加任何入站端口。

## 8. 真机测试前还缺什么

仅有 `.p8` 还不能收到通知。后续代码需要完成：

1. iOS 请求用户允许通知。
2. iOS 调用 `registerForRemoteNotifications()`。
3. iOS 获取 device token，并通过鉴权 API 上传到 BikeGoGo 后端。
4. 后端按用户保存 Sandbox/Production device token。
5. 好友申请或小队邀请时，后端向 APNs 发送普通 `alert` 推送。
6. 用户退出账号时解绑 token；APNs 返回无效 token 时及时删除。

完成后可使用 [Apple Push Notifications Console](https://developer.apple.com/notifications/push-notifications-console/)
向真机 device token 发送测试通知，并查看开发环境投递日志。

## 9. 常见问题

### Download 按钮是灰色

这个 Key 已经下载过。先在 Mac、下载目录或密码管理器附件中查找；确实丢失时创建新
Key、部署新 Key，确认推送正常后再撤销旧 Key。

### `InvalidProviderToken`

通常是 `.p8` 与 Key ID 不匹配、Team ID 错误、JWT 超过一小时或 NAS 时间不准。确认
NAS 已开启 NTP 自动校时。

### `DeviceTokenNotForTopic`

device token、APNs 环境和 Bundle ID 不匹配。Xcode Debug token 要发到 Sandbox；
TestFlight token 要发到 Production，`apns-topic` 必须是 `com.sssnto.BikeGoGo`。

### Key 泄漏了

立即在 Developer Portal 撤销该 Key，创建并部署新 Key，然后关闭并重建后端到 APNs
的连接。不要继续使用已泄漏私钥。

## Apple 官方资料

- [创建服务私钥](https://developer.apple.com/help/account/keys/create-a-private-key)
- [为 App ID 开启 capability](https://developer.apple.com/help/account/identifiers/enable-app-capabilities/)
- [使用 token 连接 APNs](https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns)
- [向 APNs 发送请求](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns)
- [App 注册 APNs](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns)
