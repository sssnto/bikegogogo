# BikeGoGo

BikeGoGo 是一个面向自行车骑行爱好者的 iOS + Apple Watch 应用原型，核心目标是解决两件事：

1. 骑行好友在双方同意后，可以进入稳定的实时语音房间沟通。
2. 记录骑行路线、速度、距离、时长、心率等数据，并与 Apple Watch 和 Apple 健康联动。

当前仓库处于 MVP 落地阶段，包含：

- 产品设计文档。
- 技术设计文档。
- 开发计划。
- 部署文档。
- 可通过 `swift build` 校验的核心 Swift 包。
- iOS/watchOS App 源码骨架。
- LiveKit token 后端骨架。

## 推荐开发环境

- macOS 15 或更新版本。
- Xcode 26.3 或更新版本。
- iOS 17+。
- watchOS 10+。
- Apple Developer Program 账号，后续真机、HealthKit、Push、TestFlight 都会用到。

## 目录

```text
.
├── Apps
│   ├── iOS
│   │   └── BikeGoGo
│   └── watchOS
│       └── BikeGoGoWatch
├── Sources
│   └── BikeGoGoCore
├── Tests
│   └── BikeGoGoCoreTests
├── docs
└── server
```

## 本地校验

核心模型和统计计算可以先独立构建：

```bash
swift build
swift test
```

完整 iOS/watchOS App 需要在 Xcode 中创建项目目标后，把 `Apps/iOS` 和 `Apps/watchOS` 下的源码加入对应 target。详细步骤见 [部署文档](docs/DEPLOYMENT.md)。

## 文档入口

- [产品设计](docs/PRODUCT_DESIGN.md)
- [技术设计](docs/TECHNICAL_DESIGN.md)
- [开发计划](docs/DEVELOPMENT_PLAN.md)
- [API 设计](docs/API_DESIGN.md)
- [部署文档](docs/DEPLOYMENT.md)
- [中间件准备清单](docs/MIDDLEWARE_PREP.md)
- [NAS Docker 部署](docs/NAS_DOCKER_DEPLOYMENT.md)
