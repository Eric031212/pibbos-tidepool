import XCTest
@testable import Content

final class SkinValidationTests: XCTestCase {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let clip = Clip(row: 0, frames: 2, fps: 2)

    private func manifest(actions: [String: Clip]? = nil, outfits: [String: OutfitSpec]? = nil,
                          shootingStar: Clip? = nil, drift: [String: Clip]? = nil) -> SkinManifest {
        SkinManifest(id: "t", name: "t", author: "t", version: "1", type: "skin", frameSize: 16,
                     states: Dictionary(uniqueKeysWithValues: SkinPack.requiredStates.map { ($0, clip) }),
                     actions: actions, outfits: outfits, shootingStar: shootingStar, drift: drift)
    }

    func testOutfitsKeepWrappedClipsWrapped() throws {
        let wrapped = Clip(row: 1, frames: 8, fps: 4, wrap: 4)
        let pack = try SkinPack(manifest: manifest(actions: ["dance": wrapped], outfits: ["halloween": OutfitSpec(offset: 10)]),
                                directory: repo)
        let dressed = pack.resolve("dance", outfit: "halloween").clip
        XCTAssertEqual(dressed.wrap, 4)
        XCTAssertEqual(pack.frameRects(for: dressed)[4].y, (1 + 10 + 1) * 16, "frame 4 is on the next row")
    }

    func testEveryClipIsChecked() {
        let broken = Clip(row: -1, frames: 0, fps: 0, wrap: 0)
        XCTAssertThrowsError(try SkinPack(manifest: manifest(shootingStar: broken), directory: repo))
        XCTAssertThrowsError(try SkinPack(manifest: manifest(drift: ["spring": broken]), directory: repo))
    }

    func testFramesMustFitTheSheet() {
        let wide = manifest(actions: ["long": Clip(row: 0, frames: 9, fps: 2)])
        XCTAssertThrowsError(try SkinPack.checkBounds(wide, width: 16 * 8, height: 16 * 10))
        XCTAssertNoThrow(try SkinPack.checkBounds(wide, width: 16 * 9, height: 16 * 10))
        let dressed = manifest(outfits: ["christmas": OutfitSpec(offset: 20)])
        XCTAssertThrowsError(try SkinPack.checkBounds(dressed, width: 32, height: 16 * 20), "outfit rows must fit too")
    }

    func testTheBundledSkinFitsItsSheet() throws {
        XCTAssertNoThrow(try SkinPack.load(from: repo.appendingPathComponent("Assets/Skins/pibbo")))
    }
}
