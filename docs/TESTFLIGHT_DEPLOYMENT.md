# BikeGoGo TestFlight 发布手册

当前首测版本：

```text
版本：1.0
构建号：4
iOS Bundle ID：com.sssnto.BikeGoGo
Watch Bundle ID：com.sssnto.BikeGoGo.watchkitapp
Apple Team ID：FR9RTRV9BC
```

## 1. 发布前检查

1. 在 Xcode 打开 `BikeGoGo/BikeGoGo.xcodeproj`。
2. 选择 iOS target `BikeGoGo`，确认 Team 是付费 Apple Developer Team，而不是
   `Personal Team`。
3. 选择 Watch target `BikeGoGoWatch`，确认使用同一个 Team。
4. iOS target 应包含 HealthKit、Sign in with Apple、Push Notifications，以及
   Background Modes 中的 Audio、Location updates、Remote notifications。
5. Watch target 应包含 HealthKit 和 Workout processing。
6. 在 Apple Developer Portal 确认两个 Bundle ID 的 capability 与 Xcode 一致。
7. 确认 NAS 正在运行本次代码对应的最新后端镜像和 PostgreSQL 16。

Release 构建会自动使用：

```text
aps-environment=production
BikeGoGoPushEnvironment=production
```

Debug 真机仍使用 `development`/`sandbox`。不要手工改 Info.plist 在两个环境之间切换。

## 2. 在 NAS 增加 Production APNs

保留现有 Sandbox Key：

```text
APNS_KEY_ID=CM2W9J6CX3
APNS_ENVIRONMENT=sandbox
```

在 Apple Developer Portal 创建一个 Environment 为 `Production`、Topic 为
`com.sssnto.BikeGoGo` 的 APNs Key。下载后执行：

```bash
cd /volume1/docker/bikegogogo
mv /你的下载路径/AuthKey_新KEYID.p8 secrets/apns-production-key.p8
chmod 600 secrets/apns-production-key.p8
```

在 NAS 的 `.env` 增加：

```bash
APNS_PRODUCTION_KEY_ID=新KEYID
```

`APNS_TEAM_ID` 和 `APNS_TOPIC` 与 Sandbox 共用，不需要重复配置。然后更新服务：

```bash
docker compose pull
docker compose up -d --force-recreate
docker compose logs --tail=100 bikegogogo-server
```

后端会同时连接 Sandbox 和 Production，并按 iOS 上报的环境路由 token。无需新增任何
公网端口；API 仍只暴露 NAS 反向代理的 HTTPS 服务，PostgreSQL 不映射公网端口。

若暂时没有 Production Key，服务仍能启动，Debug 推送不受影响，但 TestFlight 推送
不会送达。

## 3. 在 App Store Connect 创建 App

1. 登录 [App Store Connect](https://appstoreconnect.apple.com/)。
2. 打开“我的 App”，点击 `+`，选择“新建 App”。
3. 平台选择 iOS。
4. 名称填写 `BikeGoGo`；主要语言选择“简体中文”。
5. Bundle ID 选择 `com.sssnto.BikeGoGo`。
6. SKU 可填写 `bikegogogo-ios`，仅供后台识别。
7. 用户访问权限先选“完全访问”。

Watch App 不单独创建 App Store Connect 记录，它会嵌入 iOS 构建一起上传。

## 4. 准备 TestFlight 信息

在 TestFlight 的“测试信息”中建议填写：

测试内容：

```text
请重点测试骑行路线记录、锁屏后台定位、Apple Watch 户外单车训练联动、
小队实时位置和紧急求助、好友申请与小队语音。语音和小队功能需要两个互为好友
并加入同一小队的账号。
```

Beta App Review 联系信息必须填写可以接收邮件和电话的人。审核备注可填写：

```text
首次启动会创建访客账户，不需要预置账号。进入“我的”可以绑定 Sign in with Apple。
开始骑行后，App 使用后台定位记录路线；已配对并安装 Watch App 时会自动开始
Outdoor Cycling workout。小队语音仅允许已建立好友关系或同一小队的用户加入。
骑行页的小队 SOS 需要用户选择小队并二次确认，随后向其他成员发送临时位置。
```

小队状态提醒验收：

1. 两台 iPhone 加入同一小队，分别开始骑行并开启该小队的位置共享。
2. 点击地图左下角的小队状态，确认能看到对方距离且状态为正常。
3. 两台设备距离保持超过 500 米约 45 秒，确认只出现一次掉队本地通知。
4. 关闭其中一台的位置共享，另一台约 60 秒后应提示位置中断。
5. 恢复共享或回到 350 米内，确认状态恢复正常。
6. 在小队状态页关闭提醒，确认状态仍显示，但不再发送本地通知。

隐私政策正文已准备在 `docs/PRIVACY_POLICY.md`。外部测试或 App Store 提交前：

1. 填入真实联系邮箱。
2. 将政策部署到无需登录即可打开的 HTTPS 页面。
3. 把公网 URL 填入 App Store Connect 的“隐私政策 URL”。

App 隐私问卷按当前实现申报：

| 数据类型 | 与身份关联 | 用于跟踪 | 用途 |
| --- | --- | --- | --- |
| 姓名、电子邮件地址 | 是 | 否 | App 功能 |
| 用户 ID、设备 ID | 是 | 否 | App 功能 |
| 精确位置 | 是 | 否 | App 功能 |
| 健康、健身 | 是 | 否 | App 功能 |

实时语音当前不录音、不持久化。若以后启用 LiveKit 录制、分析或日志采集，必须在发布
前同步更新隐私政策、隐私清单和 App Store Connect 问卷。

## 5. Archive 与上传

1. 在 Xcode 顶部 scheme 选择 `BikeGoGo`。
2. 运行设备选择 `Any iOS Device (arm64)`，不要选择模拟器或 Watch scheme。
3. 菜单选择 `Product > Clean Build Folder`。
4. 菜单选择 `Product > Archive`。
5. 完成后会自动打开 Organizer；选择最新的 `BikeGoGo 1.0 (2)`。
6. 点击 `Distribute App > App Store Connect > Upload`。
7. 保持自动管理签名和上传调试符号，等待 Xcode 完成验证与上传。

首次发布前需要本机有 `Apple Distribution` 证书：

1. 打开 `Xcode > Settings > Accounts`。
2. 选择登录 BikeGoGo 开发团队的 Apple ID。
3. 选择 Team `FR9RTRV9BC`，点击 `Manage Certificates...`。
4. 点击左下角 `+`，选择 `Apple Distribution`。
5. 等待证书出现，并确认状态正常；证书对应的私钥会保存在本机钥匙串中。
6. 关闭设置窗口，重新执行 Archive 或在 Organizer 中继续 Distribute App。

不要从不可信来源导入 Distribution 证书或私钥。换 Mac 发布时，应通过 Xcode 的开发者
账号能力或受密码保护的证书备份安全迁移。

仓库也提供了 `deploy/ios/ExportOptions.plist`，需要在 CI 或命令行导出时使用：

```bash
xcodebuild -exportArchive \
  -archivePath /你的路径/BikeGoGo.xcarchive \
  -exportPath /你的路径/BikeGoGoExport \
  -exportOptionsPlist deploy/ios/ExportOptions.plist \
  -allowProvisioningUpdates
```

若再次上传相同版本，必须先在两个 target 中把 `CURRENT_PROJECT_VERSION` 同步递增为
`3`、`4` 等。iPhone 与 Watch 的构建号必须保持一致。

常见错误：

- `No profiles for ...`：两个 target 重新选择付费 Team，保持 Automatically manage
  signing，随后点击 `Try Again`。
- `No signing certificate "iOS Distribution" found`：按上面的 Manage Certificates
  步骤创建 `Apple Distribution` 证书。
- capability 不在 profile：在 Developer Portal 为对应 Bundle ID 开启 capability，
  回 Xcode 切换一次 Team 以刷新 profile。
- 构建号已使用：递增 `CURRENT_PROJECT_VERSION` 后重新 Archive。
- `ITMS-90683`：按邮件指出的权限类型补充主 App `Info.plist` 的用途说明，
  递增构建号并创建新的 Archive 后上传。
- Watch 校验失败：检查 Watch Bundle ID、companion Bundle ID 和两个 target 的版本号。

## 6. 启用测试

上传后等待 App Store Connect 完成构建处理，然后进入 TestFlight：

内部测试：

1. 先在“用户和访问”添加内部测试员。
2. 创建内部测试组并选择构建。
3. 内部测试不需要 Beta App Review，适合先验证 Production APNs 和安装链路。

外部测试：

1. 创建外部测试组，填写测试信息并添加构建。
2. 完成出口合规问答和 Beta App Review 信息。
3. 提交 Beta App Review；通过后用邮箱或公开链接邀请好友。

当前 BikeGoGo 使用 HTTPS、Sign in with Apple、APNs 和 LiveKit/WebRTC 的标准安全
通信，没有自研或非标准加密算法。由于 LiveKit/WebRTC 包含 Apple 操作系统以外的
标准加密实现，应在加密算法类型中选择“代替 Apple 操作系统加密或与之同时使用的
标准加密算法”。是否需要法国加密声明取决于 App 是否在法国商店分发，应以 App
Store Connect 后续问答的结果为准。

只有问答最终确认不需要出口合规文档时，才能在主 App 与 Watch App 的 `Info.plist`
中设置 `ITSAppUsesNonExemptEncryption` 为 `NO`。如果 App Store Connect 要求上传
文档，则应等待文档获批后使用 Apple 提供的合规代码。若后续增加自研加密算法、文件
加密、端到端加密或其他密码学功能，必须重新判断出口合规分类。

## 7. 一台 iPhone 的首轮验收

只有一台 iPhone 也可以先验证发布链路：

1. 在 TestFlight 安装构建并首次打开。
2. 允许通知、定位、麦克风和健康权限。
3. 在“我的”绑定 Sign in with Apple，确认昵称、好友码和历史仍可正常加载。
4. 开始一段短骑行，锁屏 3 至 5 分钟后确认计时和轨迹继续增长。
5. 确认 Apple Watch 自动开始户外单车训练，心率回传到 iPhone。
6. 结束骑行，确认历史显示已同步，并在 Apple 健康/健身中看到 workout。
7. 在 NAS 数据库确认出现 Production push token。

PostgreSQL 检查命令：

```bash
docker compose exec postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
"SELECT token->>'environment' AS environment, count(*)
 FROM bikegogogo_app_state,
 jsonb_array_elements(payload->'pushTokens') AS token
 GROUP BY 1;"
```

预期至少出现一条 `production`。TestFlight 与 Xcode Debug 使用不同 APNs 环境，看到
两种 token 同时保留是正常现象。

Watch App 会随 iPhone 构建一起分发。若没有自动安装，在 iPhone 的 Watch App 中打开
“我的手表”，滚动到“可用 App”，点击 BikeGoGo 旁的“安装”。

## 8. 两台 iPhone 的完整验收

获得第二台测试设备后再完成：

1. 两个不同账号互加好友并通过申请，验证双方 Production 推送。
2. 建立小队并邀请另一方，验证小队邀请推送。
3. A 向 B 发起好友语音，验证 B 在前台显示接听页、后台或锁屏收到带声音的通知。
4. B 接听后，两端确认本机显示“麦克风已发送”、对方显示“语音已接收”，然后轮流
   说话和静音，验证双向音频。
5. 发起小队语音并验证所有其他成员均收到邀请；测试拒绝、取消和 90 秒自动过期。
6. 通话中测试锁屏、后台和 Wi-Fi/蜂窝切换。
7. 同一 Apple 账号在另一设备登录，验证云端骑行历史恢复。
8. 同时编辑或删除骑行记录，观察同步冲突和错误提示。
9. 在“我的 > 账户与隐私”导出 JSON，确认系统分享面板可用且文件不含登录或推送
   token。
10. 使用专门创建的测试账号执行永久删除，确认旧好友关系和历史消失、旧会话失效，
    且 App 自动进入一个全新的访客账户。

通过这一轮后，阶段 5 的“小规模 TestFlight 内测”才算完整验收。
