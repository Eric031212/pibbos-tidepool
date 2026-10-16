import XCTest
@testable import Content

final class TransitionTests: XCTestCase {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func manifest(poses: [String: String], transitions: [String: Clip]) -> SkinManifest {
        let clip = Clip(row: 0, frames: 2, fps: 2)
        return SkinManifest(id: "t", name: "t", author: "t", version: "1", type: "skin", frameSize: 16,
                            states: Dictionary(uniqueKeysWithValues: SkinPack.requiredStates.map { ($0, clip) }),
                            actions: nil, poses: poses, transitions: transitions)
    }

    func testMostSpecificKeyWins() throws {
        let rise = Clip(row: 1, frames: 3, fps: 10, loop: false)
        let doze = Clip(row: 2, frames: 2, fps: 4, loop: false)
        let exact = Clip(row: 3, frames: 1, fps: 4, loop: false)
        let pack = try SkinPack(manifest: manifest(
            poses: ["hidden": "low", "chill": "up", "sleep": "up", "music": "up"],
            transitions: ["@low>@up": rise, "@up>sleep": doze, "chill>music": exact]), directory: repo)
        XCTAssertEqual(pack.transition(from: "hidden", to: "chill"), rise)
        XCTAssertEqual(pack.transition(from: "hidden", to: "sleep"), rise, "pose pair when nothing closer")
        XCTAssertEqual(pack.transition(from: "chill", to: "sleep"), doze, "@pose>clip beats @pose>@pose")
        XCTAssertEqual(pack.transition(from: "chill", to: "music"), exact)
        XCTAssertNil(pack.transition(from: "chill", to: "hidden"), "no key: cut straight over")
        XCTAssertNil(pack.transition(from: "chill", to: "chill"))
    }

    func testSkinsWithoutTransitionsCut() throws {
        let pack = try SkinPack(manifest: manifest(poses: [:], transitions: [:]), directory: repo)
        XCTAssertNil(pack.transition(from: "hidden", to: "chill"))
    }

    func testBundledSkinGlidesBetweenPosesAndWearsOutfits() throws {
        let pack = try SkinPack.load(from: repo.appendingPathComponent("Assets/Skins/pibbo"))
        let rise = try XCTUnwrap(pack.transition(from: "hidden", to: "chill"))
        XCTAssertFalse(rise.loops)
        XCTAssertNotNil(pack.transition(from: "chill", to: "hidden"))
        XCTAssertNotNil(pack.transition(from: "hidden", to: "peek"))
        XCTAssertNotNil(pack.transition(from: "submerged", to: "chill"))
        XCTAssertNotNil(pack.transition(from: "chill", to: "backfloat"))
        XCTAssertNotEqual(pack.transition(from: "chill", to: "sleep"), pack.transition(from: "chill", to: "music"))
        let spec = try XCTUnwrap(pack.manifest.outfits?["christmas"])
        XCTAssertEqual(pack.transition(from: "hidden", to: "chill", outfit: "christmas")?.row, rise.row + spec.offset)
        // Every transition, in every outfit, is inside the sheet.
        let png = try Data(contentsOf: pack.spriteSheetURL)
        let sheetRows = png[20..<24].reduce(0) { $0 << 8 | Int($1) } / pack.manifest.frameSize
        let deepest = (pack.manifest.transitions ?? [:]).values.map(\.row).max()! + (pack.manifest.outfits ?? [:]).values.map(\.offset).max()!
        XCTAssertLessThan(deepest, sheetRows)
    }

    func testTransitionsKeepPlaybackShort() throws {
        // Brain's timings (e.g. look 1.5 s, unplug 1.6 s) start when the clip is
        // shown, so in-betweens must stay brief.
        let pack = try SkinPack.load(from: repo.appendingPathComponent("Assets/Skins/pibbo"))
        for (key, clip) in pack.manifest.transitions ?? [:] {
            XCTAssertLessThanOrEqual(Double(clip.frames) / clip.fps, 0.6, key)
        }
    }
}
