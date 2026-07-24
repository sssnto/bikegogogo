# BikeGoGo 开发计划

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

待完成：

- Xcode target 添加 LiveKit Swift SDK。
- `VoiceRoomClient` 使用 LiveKit `Room` 真实连接。
- 音频后台模式真机测试。

## 阶段 5：账号、好友和云同步

目标：可小规模内测。

- Apple 登录。
- 好友申请和同意。
- 小队管理。
- 骑行记录上传。
- 历史记录云同步。
- APNs 推送。

验收：

- 通过 TestFlight 给好友安装。
- 不同账号之间可建立好友关系并语音。

## 阶段 6：上架准备

目标：提交 App Store 审核。

- 完成隐私政策。
- 完成权限说明。
- 完成 App Store 截图和描述。
- 处理后台定位、HealthKit、麦克风审核说明。
- 崩溃和日志收集。
