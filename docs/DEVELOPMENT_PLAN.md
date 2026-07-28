# BikeGoGo 开发计划

## 当前进度

截至 2026-07-28：

- 阶段 1：开发完成，iOS 和 Watch target 均可构建。
- 阶段 2：开发完成，等待 iPhone 真机完成锁屏和长距离骑行验收。
- 阶段 3：开发完成，iPhone 可唤醒 Watch 并自动开始户外单车训练，等待双真机验收。
- 阶段 4：开发完成，两台 iPhone 双向语音和来电提醒已通过真机验收。
- 阶段 5：主体功能完成。账号、好友、小队、多人语音鉴权和骑行云同步已完成；
  APNs 社交通知和 PostgreSQL 生产迁移已完成。
- 阶段 6：进行中。Release 推送环境、隐私清单、版本号和 TestFlight 发布资料已完成，
  等待首次 Archive 上传及 TestFlight 真机验收。
- 阶段 7：进行中。小队临时位置共享已通过真机验收，紧急求助功能已完成开发，
  等待两台 iPhone 做 APNs 和地图跳转验收。

## 阶段 1：工程和静态原型

目标：建立工程结构和主要界面。

- 创建核心 Swift 包。
- 创建 iOS App target。
- 创建 watchOS App target。
- 首页、骑行页、好友页、历史页。
- 使用模拟数据跑通 UI。

验收：

- iOS App 能在模拟器启动。
- Watch App 能在模拟器启动。
- `swift test` 通过。

## 阶段 2：骑行记录 MVP

目标：手机可以记录一条真实骑行。

- CoreLocation 权限申请。
- 开始/暂停/继续/结束。
- 后台位置更新。
- 轨迹点存储。
- 地图轨迹展示。
- 统计距离、速度、时长。
- 本地 JSON 持久化。
- GPX 导出。

验收：

- 锁屏后能继续记录。
- 骑行结束后能看到路线和统计。
- 关闭 App 后能重新读取历史记录。
- 可从骑行详情生成并分享 GPX 文件。

## 阶段 3：Apple Watch MVP

目标：Watch 可以参与记录和控制。

- HealthKit 授权。
- `HKWorkoutSession` outdoor cycling。
- 实时心率和距离。
- 与 iPhone 同步状态。
- 保存 workout 到 Apple 健康。

验收：

- Watch 真机上能开始 workout。
- iPhone 能收到 Watch 的状态和心率。

前置条件：

- Apple Developer Program 审核通过。
- iPhone 和 Apple Watch 已配对。
- iOS App 与 Watch App 使用同一个开发团队签名。
- HealthKit capability 已开启。

## 阶段 4：语音 MVP

目标：好友小队可实时语音。

- 接入 LiveKit Swift SDK。
- 后端生成 room token。
- 加入/退出房间。
- 静音/解除静音。
- 后台音频。
- 自动重连。

验收：

- 两台 iPhone 真机能语音。
- 锁屏、切后台、网络切换后能恢复。

中间件：

- LiveKit Cloud 或自建 LiveKit。
- 后端 token endpoint。

当前已完成：

- 后端 LiveKit token endpoint 骨架。
- iOS token 请求客户端。
- Xcode target 已添加 LiveKit Swift SDK 2.x。
- `VoiceRoomClient` 已使用 LiveKit `Room` 真实连接。
- 已实现加入、退出、静音、成员状态和重连状态。

待真机验收：

- 两台 iPhone 同房间通话。
- 锁屏、切后台、Wi-Fi/蜂窝网络切换后的语音恢复。

## 阶段 5：账号、好友和云同步

目标：可小规模内测。

- Apple 登录。
- 好友申请和同意。
- 小队管理。
- 骑行记录上传。
- 历史记录云同步。
- APNs 推送。

当前已完成：

- 设备绑定的访客账户，可原地升级绑定 Apple ID。
- 服务端验证 Apple JWT 签名、Bundle ID、有效期和 nonce。
- iOS 会话保存在 Keychain，服务端会话默认 30 天过期并支持退出。
- 用户中心、昵称编辑和 8 位好友码。
- 好友申请发送、接受、拒绝和好友列表。
- NAS JSON 数据持久化与 Docker 数据卷。
- 登录账户作为 LiveKit 语音身份，匿名 token 请求已关闭。
- 语音房间强制校验双方好友关系，并支持在语音页选择通话好友。
- 小队创建、好友邀请、成员移出/退出、解散和小队多人语音。
- 完成骑行后自动上传；启动、手动刷新时同步账号历史；支持云端删除。
- 公网接口已增加全局及登录/语音专项限流。
- APNs Sandbox 与 Production 双通道已接入：Debug 和 TestFlight/App Store 自动使用
  对应环境，iOS 自动绑定/解绑 device token，失效 token 会自动清理。
- 服务端 JSON 数据格式已迁移到 v4，新增按账号及 APNs 环境隔离的推送 token。
- PostgreSQL 16 已接管主存储，旧 JSON 会首次自动导入并保留不可覆盖的迁移前备份。
- 所有写操作使用数据库原子更新和版本冲突检测，JSON 继续作为滚动镜像供备份与回滚。
- 健康检查会验证数据库连接并报告当前存储后端；CI 使用真实 PostgreSQL 16 验证迁移和重启。

下一步：

- 在 NAS 配置 APNs Production Key，并上传首个 TestFlight 构建。
- 多台 iPhone 的语音、云同步冲突和长距离路线容量验收。
- TestFlight 扩大内测后，将 PostgreSQL 单行 JSONB 状态逐步拆分为规范化业务表。

验收：

- 通过 TestFlight 给好友安装。
- 不同账号之间可建立好友关系、组建小队并语音。
- 同一 Apple 账号重新安装后可恢复云端骑行历史。

## 阶段 6：上架准备

目标：提交 App Store 审核。

- 发布隐私政策到公网 URL。
- 隐私清单和权限说明已完成。
- TestFlight 元数据已完成，待制作 App Store 截图。
- 处理后台定位、HealthKit、麦克风审核说明。
- 崩溃和日志收集。

## 阶段 7：组队骑行增强

目标：让骑行小队在真实骑行中更容易保持队形并了解成员状态。

当前已完成：

- 骑行页可选择已加入的小队，主动开启或停止位置共享。
- 地图展示其他共享成员的昵称、最近位置和速度。
- 共享默认关闭，定位数据通过现有 HTTPS 鉴权接口传输。
- 服务端位置 90 秒自动过期，不写入 PostgreSQL；停止骑行、退出或解散小队时清除。
- 服务端接口、过期逻辑和 iOS 模拟器构建已通过自动化验证。
- 骑行地图提供醒目的 SOS 入口，选择小队后二次确认发送。
- SOS 自动刷新发送者临时位置，并通过 APNs 提醒其他成员。
- 接收方在 App 内可查看求助人和小队，并直接打开 Apple 地图定位。

真机验收：

- 两台 iPhone 加入同一小队并开始骑行，双方地图能在约 15 秒内看到对方。
- 锁屏、前后台切换后位置仍能按系统授权情况更新。
- 停止共享或结束骑行后，对方地图上的位置在 90 秒内消失。
- 非小队成员不能读取或提交该小队位置。
- 一台 iPhone 发送 SOS 后，另一台能收到求助提醒并打开正确地图位置。
- 无准确 GPS 时不能发送；10 分钟内超过 3 次请求会被服务端限流。

下一步：

- 增加偏离队伍和成员长时间未更新提醒。
- 结合真实户外轨迹调整上报间隔、精度门槛和电量消耗。
