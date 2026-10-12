// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SignalsSpike",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "SignalsSpike", path: "Sources/SignalsSpike")
    ]
)
