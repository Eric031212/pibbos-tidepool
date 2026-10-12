// swift-tools-version:5.9
// Platform-independent core of Tidepool (Foundation only, no AppKit), so a
// later Windows port can reuse it unchanged. The macOS app (project.yml)
// depends on these libraries. Run the tests with `swift test`.
import PackageDescription

let package = Package(
    name: "TidepoolCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "Brain", targets: ["Brain"]),
        .library(name: "Content", targets: ["Content"]),
        .library(name: "Strings", targets: ["Strings"]),
    ],
    targets: [
        .target(name: "Brain", path: "Sources/Brain"),
        .target(name: "Content", path: "Sources/Content"),
        .target(name: "Strings", path: "Sources/Strings"),
        .testTarget(name: "BrainTests", dependencies: ["Brain"], path: "Tests/BrainTests"),
        .testTarget(name: "ContentTests", dependencies: ["Content"], path: "Tests/ContentTests"),
    ]
)
