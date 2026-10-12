// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WindowSpike",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "WindowSpike", path: "Sources/WindowSpike")
    ]
)
