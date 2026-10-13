import XCTest
@testable import Content
import Strings

final class SkinPackTests: XCTestCase {
    func manifest(states: [String] = SkinPack.requiredStates,
                  actions: [String: Clip]? = nil,
                  type: String = "skin") -> SkinManifest {
        var clips: [String: Clip] = [:]
        for (row, name) in states.enumerated() { clips[name] = Clip(row: row, frames: 4, fps: 4) }
        return SkinManifest(id: "test", name: "test", author: "me", version: "1.0.0",
                            type: type, frameSize: 16, states: clips, actions: actions)
    }

    func testBundledPackLoads() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let pack = try SkinPack.load(from: repo.appendingPathComponent("Assets/Skins/pibbo"))
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

final class GardenAndFontTests: XCTestCase {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func testBundledSkinHasAGarden() throws {
        let pack = try SkinPack.load(from: repo.appendingPathComponent("Assets/Skins/pibbo"))
        let garden = try XCTUnwrap(pack.manifest.garden)
        XCTAssertEqual(pack.gardenFrameRect(stage: 0), FrameRect(x: 0, y: garden.row * 16, width: 16, height: 16))
        XCTAssertEqual(pack.gardenFrameRect(stage: 99)?.x, (garden.stages - 1) * 16, "clamped to the last stage")
        XCTAssertFalse(pack.availableActions.contains("submerged"))
        XCTAssertTrue(pack.availableActions.contains("water"))
    }

    func testSkinWithoutGarden() throws {
        let clips = Dictionary(uniqueKeysWithValues: SkinPack.requiredStates.enumerated().map { ($1, Clip(row: $0, frames: 1, fps: 1)) })
        let pack = try SkinPack(manifest: SkinManifest(id: "a", name: "a", author: "a", version: "1", type: "skin",
                                                       frameSize: 16, states: clips, actions: nil),
                                directory: URL(fileURLWithPath: "/"))
        XCTAssertNil(pack.gardenFrameRect(stage: 0))
    }

    func testFontLayout() throws {
        let font = try PixelFont(json: Data(contentsOf: repo.appendingPathComponent("Assets/UI/ui.json")))
        XCTAssertEqual(font.lineHeight, 9)
        let (placed, width) = font.layout("hi")
        XCTAssertEqual(placed.count, 2)
        XCTAssertEqual(placed[1].x, font.glyphs["h"]!.w + font.letterSpacing)
        XCTAssertEqual(width, font.glyphs["h"]!.w + 1 + font.glyphs["i"]!.w)

        // Emoji with and without the variation selector map to the same icon.
        XCTAssertEqual(font.layout("❄️").placed.first?.glyph, font.glyphs["❄"])
        XCTAssertEqual(font.layout("🎧").placed.first?.glyph, font.glyphs["🎧"])
        // Unknown characters fall back to "?".
        XCTAssertEqual(font.layout("€").placed.first?.glyph, font.glyphs["?"])
    }

    func testEveryBuiltInBubbleStringIsDrawable() throws {
        let font = try PixelFont(json: Data(contentsOf: repo.appendingPathComponent("Assets/UI/ui.json")))
        for text in Strings.allPixelText {
            for character in text {
                let key = String(character).replacingOccurrences(of: "\u{FE0F}", with: "")
                XCTAssertNotNil(font.glyphs[key], "missing glyph '\(key)' in '\(text)'")
            }
        }
    }
}
