// swift-tools-version:5.9
import PackageDescription

// 译镜 App 的核心逻辑：与界面、相机无关，可以在 macOS 上直接用 `swift test` 验证。
let package = Package(
    name: "LensCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "LensCore", targets: ["LensCore"]),
    ],
    targets: [
        .target(name: "LensCore"),
        .testTarget(name: "LensCoreTests", dependencies: ["LensCore"]),
    ]
)
