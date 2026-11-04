import XCTest
@testable import Content

final class OutfitTests: XCTestCase {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func testBundledSkinDressesUpForEveryHoliday() throws {
        let pack = try SkinPack.load(from: repo.appendingPathComponent("Assets/Skins/pibbo"))
        for holiday in ["halloween", "christmas", "newYear", "lunarNewYear"] {
            let spec = try XCTUnwrap(pack.manifest.outfits?[holiday], holiday)
            let dressed = pack.resolve("chill", outfit: holiday)
            XCTAssertEqual(dressed.name, "chill")
            XCTAssertEqual(dressed.clip.row, pack.resolve("chill").clip.row + spec.offset)
        }
    }

    func testOutfitKeepsFallbacksAndUnknownOutfitsArePlain() throws {
        let pack = try SkinPack.load(from: repo.appendingPathComponent("Assets/Skins/pibbo"))
        XCTAssertEqual(pack.resolve("chill", outfit: "valentines").clip, pack.resolve("chill").clip)
        XCTAssertEqual(pack.resolve("chill", outfit: nil).clip, pack.resolve("chill").clip)
        XCTAssertEqual(pack.resolve("nosuchaction", outfit: "halloween").name, "chill", "fallback still applies")
    }

    func testOutfitRowsFitInTheSheet() throws {
        let pack = try SkinPack.load(from: repo.appendingPathComponent("Assets/Skins/pibbo"))
        let rows = (pack.manifest.states.values.map(\.row) + (pack.manifest.actions ?? [:]).values.map(\.row)).max()!
        let deepest = rows + (pack.manifest.outfits ?? [:]).values.map(\.offset).max()!
        // sprites.png height from its PNG header (IHDR: big-endian UInt32 at byte 20)
        let png = try Data(contentsOf: pack.spriteSheetURL)
        let height = png[20..<24].reduce(0) { $0 << 8 | Int($1) }
        let sheetRows = height / pack.manifest.frameSize
        XCTAssertLessThan(deepest, sheetRows)
    }
}

final class DecorTests: XCTestCase {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func testBundledSkinDecoratesHalloweenOnly() throws {
        let pack = try SkinPack.load(from: repo.appendingPathComponent("Assets/Skins/pibbo"))
        let halloween = try XCTUnwrap(pack.decor(for: "halloween"))
        XCTAssertGreaterThan(halloween.frames, 1)
        XCTAssertNil(pack.decor(for: nil))
        XCTAssertNil(pack.decor(for: "valentines"))
        let png = try Data(contentsOf: pack.spriteSheetURL)
        let sheetRows = png[20..<24].reduce(0) { $0 << 8 | Int($1) } / pack.manifest.frameSize
        XCTAssertLessThan(halloween.row, sheetRows)
    }

    func testNoDecorWithoutAGarden() throws {
        let clip = Clip(row: 0, frames: 2, fps: 2)
        let manifest = SkinManifest(id: "t", name: "t", author: "t", version: "1", type: "skin", frameSize: 16,
                                    states: Dictionary(uniqueKeysWithValues: SkinPack.requiredStates.map { ($0, clip) }),
                                    actions: nil, decor: ["halloween": clip])
        XCTAssertNil(try SkinPack(manifest: manifest, directory: repo).decor(for: "halloween"))
    }
}

final class WinterDecorTests: XCTestCase {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func testEveryHolidayHasSomethingOnTheRocks() throws {
        let pack = try SkinPack.load(from: repo.appendingPathComponent("Assets/Skins/pibbo"))
        for holiday in ["halloween", "christmas", "newYear", "lunarNewYear"] {
            let some = pack.decor(for: holiday) != nil || pack.meadowDecor(for: holiday) != nil
            XCTAssertTrue(some, holiday)
        }
    }

    func testNewYearNightsHaveFireworks() throws {
        let pack = try SkinPack.load(from: repo.appendingPathComponent("Assets/Skins/pibbo"))
        XCTAssertNil(pack.decor(for: "newYear"), "no fireworks by day")
        let fireworks = try XCTUnwrap(pack.decor(for: "newYear", night: true))
        XCTAssertEqual(fireworks, pack.manifest.decor?["newYear@night"])
        XCTAssertNotNil(pack.meadowDecor(for: "newYear"), "bunting by day")
        XCTAssertEqual(pack.decor(for: "halloween", night: true), pack.decor(for: "halloween"), "no night variant: same decor")
    }
}
