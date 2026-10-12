import XCTest
@testable import Content

final class SkinPackTests: XCTestCase {
    func manifest(states: [String] = SkinPack.requiredStates,
                  actions: [String: Clip]? = nil,
                  type: String = "skin") -> SkinManifest {
        var clips: [String: Clip] = [:]
        for (row, name) in states.enumerated() { clips[name] = Clip(row: row, frames: 4, fps: 4) }
        return SkinManifest(id: "test", name: "test", author: "me", version: "1.0.0",
                            type: type, frameSize: 16, states: clips, actions: actions)
    }

    func testPlaceholderPackLoads() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let pack = try SkinPack.load(from: repo.appendingPathComponent("Assets/Placeholder/pibbo"))
        XCTAssertEqual(pack.manifest.frameSize, 16)
        XCTAssertEqual(pack.resolve("submerged").name, "submerged")
        XCTAssertTrue(FileManager.default.fileExists(atPath: pack.spriteSheetURL.path))
    }

    func testRejectsMissingRequiredStates() {
        XCTAssertThrowsError(try SkinPack(manifest: manifest(states: ["hidden", "peek", "chill"]), directory: URL(fileURLWithPath: "/"))) {
            XCTAssertEqual($0 as? SkinError, .missingStates(["music", "sleep"]))
        }
    }

    func testRejectsNonSkinPacks() {
        XCTAssertThrowsError(try SkinPack(manifest: manifest(type: "music"), directory: URL(fileURLWithPath: "/"))) {
            XCTAssertEqual($0 as? SkinError, .notASkin(type: "music"))
        }
    }

    func testRejectsImpossibleClips() {
        let bad = manifest(actions: ["stretch": Clip(row: 6, frames: 0, fps: 4)])
        XCTAssertThrowsError(try SkinPack(manifest: bad, directory: URL(fileURLWithPath: "/"))) {
            XCTAssertEqual($0 as? SkinError, .invalidClip("stretch"))
        }
    }

    func testFallbacks() throws {
        let pack = try SkinPack(manifest: manifest(actions: ["stretch": Clip(row: 5, frames: 2, fps: 2)]),
                                directory: URL(fileURLWithPath: "/"))
        XCTAssertEqual(pack.resolve("music").name, "music")
        XCTAssertEqual(pack.resolve("stretch").name, "stretch")
        XCTAssertEqual(pack.resolve("cocoa").name, "chill", "missing actions fall back to chill")
        XCTAssertEqual(pack.resolve("submerged").name, "hidden", "missing submerged falls back to hidden")
        XCTAssertEqual(pack.availableActions, ["stretch"])
    }

    func testFrameRects() throws {
        let pack = try SkinPack(manifest: manifest(), directory: URL(fileURLWithPath: "/"))
        XCTAssertEqual(pack.frameRects(for: Clip(row: 2, frames: 3, fps: 4)), [
            FrameRect(x: 0, y: 32, width: 16, height: 16),
            FrameRect(x: 16, y: 32, width: 16, height: 16),
            FrameRect(x: 32, y: 32, width: 16, height: 16),
        ])
    }
}
