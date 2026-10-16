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
