// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "BattSignal",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "BattSignalCore"),
        .executableTarget(name: "BattSignal", dependencies: ["BattSignalCore"]),
        .testTarget(name: "BattSignalCoreTests", dependencies: ["BattSignalCore"]),
    ]
)
