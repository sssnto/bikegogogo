// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "BikeGoGo",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14)
    ],
    products: [
        .library(name: "BikeGoGoCore", targets: ["BikeGoGoCore"])
    ],
    targets: [
        .target(name: "BikeGoGoCore"),
        .testTarget(name: "BikeGoGoCoreTests", dependencies: ["BikeGoGoCore"])
    ]
)
