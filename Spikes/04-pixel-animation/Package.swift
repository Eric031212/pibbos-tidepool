// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AnimSpike",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "AnimSpike", path: "Sources/AnimSpike")
    ]
)
