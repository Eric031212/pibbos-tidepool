// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MusicSpike",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "MusicSpike", path: "Sources/MusicSpike")
    ]
)
