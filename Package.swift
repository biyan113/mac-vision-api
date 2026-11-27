// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "vision-api",
    platforms: [
       .macOS(.v13)
    ],
    products: [
        // 可嵌入到其他 Vapor 应用中的库：`try await VisionAPI.configure(app)`
        .library(name: "VisionAPI", targets: ["VisionAPI"]),
        // 开箱即用的服务端可执行文件
        .executable(name: "App", targets: ["App"]),
        // AppKit 桌面应用
        .executable(name: "VisionApp", targets: ["VisionApp"]),
        // 供 AI 助手调用的 MCP 服务（标准输入输出）
        .executable(name: "VisionMCP", targets: ["VisionMCP"]),
    ],
    dependencies: [
        // 💧 A server-side Swift web framework.
        .package(url: "https://github.com/vapor/vapor.git", from: "4.99.3"),
        // 🔵 Non-blocking, event-driven networking for Swift. Used for custom executors
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/dankinsoid/VaporToOpenAPI.git", from: "4.7.1")
    ],
    targets: [
        .target(
            name: "VisionAPI",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                "VaporToOpenAPI"
            ],
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "App",
            dependencies: [
                .target(name: "VisionAPI"),
                .product(name: "Vapor", package: "vapor"),
            ],
            swiftSettings: swiftSettings
        ),
        // 不依赖 Vapor 和 AppKit 的 Vision / PDFKit 封装，供桌面应用和 MCP 服务使用
        .target(
            name: "VisionCore",
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "VisionApp",
            dependencies: [
                "VisionCore",
                .target(name: "VisionAPI"),
                .product(name: "Vapor", package: "vapor"),
            ]
        ),
        .executableTarget(
            name: "VisionMCP",
            dependencies: ["VisionCore"]
        ),
        .testTarget(
            name: "VisionCoreTests",
            dependencies: ["VisionCore"]
        ),
        .testTarget(
            name: "VisionAPITests",
            dependencies: [
                .target(name: "VisionAPI"),
                .product(name: "XCTVapor", package: "vapor"),
            ],
            swiftSettings: swiftSettings
        )
    ],
    swiftLanguageModes: [.v5]
)

var swiftSettings: [SwiftSetting] { [
    .enableUpcomingFeature("DisableOutwardActorInference"),
    .enableExperimentalFeature("StrictConcurrency"),
] }
