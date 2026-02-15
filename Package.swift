// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BridgeDiffNative",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BridgeDiffNative", targets: ["BridgeDiffNative"])
    ],
    targets: [
        .executableTarget(name: "BridgeDiffNative")
    ]
)
