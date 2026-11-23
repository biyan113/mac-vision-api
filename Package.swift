// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "vision-api",
    platforms: [
       .macOS(.v13)
    ],
    dependencies: [
        // 💧 A server-side Swift web framework.
        .package(url: "https://github.com/vapor/vapor.git", from: "4.99.3"),
        // 🔵 Non-blocking, event-driven networking for Swift. Used for custom executors
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/dankinsoid/VaporToOpenAPI.git", from: "4.7.1")
    ],
    targets: [
        // 纯 Vision / PDFKit 逻辑，不依赖 Vapor 和 AppKit，供服务端与图形界面共用
        .target(
            name: "VisionCore",
            swiftSettings: swiftSettings
        ),
        // Vapor 路由、控制器与可内嵌的服务器
        .target(
            name: "VisionServer",
            dependencies: [
                "VisionCore",
                .product(name: "Vapor", package: "vapor"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                "VaporToOpenAPI"
            ],
            swiftSettings: swiftSettings
        ),
        // 命令行 HTTP 服务入口
        .executableTarget(
            name: "App",
            dependencies: [
                "VisionServer",
                .product(name: "Vapor", package: "vapor"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio")
            ],
            swiftSettings: swiftSettings
        ),
        // AppKit 图形界面
        .executableTarget(
            name: "VisionApp",
            dependencies: [
                "VisionCore",
                "VisionServer"
            ]
        ),
        .testTarget(
            name: "AppTests",
            dependencies: [
                "VisionServer",
                .product(name: "XCTVapor", package: "vapor"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "VisionCoreTests",
            dependencies: [
                "VisionCore"
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)

var swiftSettings: [SwiftSetting] { [
    .enableUpcomingFeature("DisableOutwardActorInference"),
    .enableExperimentalFeature("StrictConcurrency"),
] }
