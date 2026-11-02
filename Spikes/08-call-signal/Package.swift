// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CallSpike",
    platforms: [.macOS(.v13)],
    targets: [.executableTarget(name: "CallSpike", linkerSettings: [
        .linkedFramework("CoreMediaIO"), .linkedFramework("CoreAudio"), .linkedFramework("AppKit"),
    ])]
)
