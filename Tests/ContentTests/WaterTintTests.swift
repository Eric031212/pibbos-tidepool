import XCTest
@testable import Content

final class WaterTintTests: XCTestCase {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// One 1-pixel-wide column of two 4-row frames, every pixel the same colour.
    private func column(_ rgb: (UInt8, UInt8, UInt8), alpha: UInt8 = 255) -> [UInt8] {
        Array(repeating: [rgb.0, rgb.1, rgb.2, alpha], count: 8).flatMap { $0 }
    }

    func testRecolorsOnlyTheWaterRowsOfEachFrame() throws {
        let tint = try XCTUnwrap(WaterTint(hex: ["#6fb7d9": "3a548a"]))
        var pixels = column((0x6f, 0xb7, 0xd9))
        pixels.withUnsafeMutableBufferPointer { tint.recolor($0, width: 1, height: 8, frameSize: 4) }
        let rows = stride(from: 0, to: pixels.count, by: 4).map { Array(pixels[$0..<$0 + 3]) }
        let water: [UInt8] = [0x3a, 0x54, 0x8a], dry: [UInt8] = [0x6f, 0xb7, 0xd9]
        // frameSize 4 → row 0 dry, rows 1-3 water, in both frames
        XCTAssertEqual(rows, [dry, water, water, water, dry, water, water, water])
    }

    func testLeavesOtherColoursAndSeeThroughPixels() throws {
        let tint = try XCTUnwrap(WaterTint(hex: ["6fb7d9": "3a548a"]))
        var other = column((1, 2, 3))
        other.withUnsafeMutableBufferPointer { tint.recolor($0, width: 1, height: 8, frameSize: 4) }
        XCTAssertEqual(other, column((1, 2, 3)))
        var faint = column((0x6f, 0xb7, 0xd9), alpha: 128)
        faint.withUnsafeMutableBufferPointer { tint.recolor($0, width: 1, height: 8, frameSize: 4) }
        XCTAssertEqual(faint, column((0x6f, 0xb7, 0xd9), alpha: 128))
    }

    func testRejectsBadHex() {
        XCTAssertNil(WaterTint(hex: ["nope": "123"]))
        XCTAssertEqual(WaterTint(hex: ["000000": "zzzzzz", "6fb7d9": "3a548a"])?.colors, [0x6fb7d9: 0x3a548a])
    }

    func testBundledSkinColoursDawnDuskAndNight() throws {
        let pack = try SkinPack.load(from: repo.appendingPathComponent("Assets/Skins/pibbo"))
        for time in ["dawn", "dusk", "night"] {
            XCTAssertEqual(pack.waterTint(for: time)?.colors.count, 3, time)
        }
        XCTAssertNil(pack.waterTint(for: "day"), "daytime keeps the sheet's colours")
        XCTAssertNil(pack.waterTint(for: nil))
    }
}
