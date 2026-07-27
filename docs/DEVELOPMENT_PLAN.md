# BikeGoGo 开发计划

## 当前进度

截至 2026-07-27：

- 阶段 1：开发完成，iOS 和 Watch target 均可构建。
- 阶段 2：开发完成，等待 iPhone 真机完成锁屏和长距离骑行验收。
- 阶段 3：开发完成，iPhone 可唤醒 Watch 并自动开始户外单车训练，等待双真机验收。
- 阶段 4：开发完成，LiveKit 和线上 token 接口已接通，等待两台 iPhone 做网络切换与后台语音验收。
- 阶段 5：主体功能完成。账号、好友、小队、多人语音鉴权和骑行云同步已完成；
  PostgreSQL 生产迁移与 APNs 通知待下一批开发。
- 阶段 6：尚未开始。

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
- 服务端 JSON 数据格式已迁移到 v3，用户、好友、小队和骑行记录都保存在 Docker 数据卷。
- 公网接口已增加全局及登录/语音专项限流。

下一步：

- PostgreSQL 16 数据层迁移，替代当前适合小规模真机测试的单文件存储。
- APNs 好友申请和小队邀请通知。
- 多台 iPhone 的语音、云同步冲突和长距离路线容量验收。

验收：

- 通过 TestFlight 给好友安装。
- 不同账号之间可建立好友关系、组建小队并语音。
- 同一 Apple 账号重新安装后可恢复云端骑行历史。

## 阶段 6：上架准备

目标：提交 App Store 审核。

- 完成隐私政策。
- 完成权限说明。
- 完成 App Store 截图和描述。
- 处理后台定位、HealthKit、麦克风审核说明。
- 崩溃和日志收集。
