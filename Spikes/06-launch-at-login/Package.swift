// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LoginSpike",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "LoginSpike", path: "Sources/LoginSpike")
    ]
)
