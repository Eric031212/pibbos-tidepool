// swift-tools-version:5.9
// Platform-independent core of Tidepool: Brain, Content, Strings, World
// (Foundation only, no AppKit), so a later Windows port can reuse it unchanged.
// The macOS app (project.yml) depends on these libraries. Run the tests with
// `swift test`.
import PackageDescription

let package = Package(
    name: "TidepoolCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "Brain", targets: ["Brain"]),
        .library(name: "Content", targets: ["Content"]),
        .library(name: "Strings", targets: ["Strings"]),
        .library(name: "World", targets: ["World"]),
    ],
    targets: [
        .target(name: "Brain", dependencies: ["World"], path: "Sources/Brain"),
        .target(name: "Content", path: "Sources/Content"),
        .target(name: "Strings", path: "Sources/Strings"),
        .target(name: "World", path: "Sources/World"),
        .testTarget(name: "BrainTests", dependencies: ["Brain"], path: "Tests/BrainTests"),
        .testTarget(name: "ContentTests", dependencies: ["Content", "Strings"], path: "Tests/ContentTests"),
        .testTarget(name: "WorldTests", dependencies: ["World"], path: "Tests/WorldTests"),
    ]
)
