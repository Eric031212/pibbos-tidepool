import XCTest
@testable import Content

final class MusicLibraryTests: XCTestCase {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func track(_ name: String) -> MusicLibrary.Track {
        MusicLibrary.Track(title: name, url: URL(fileURLWithPath: "/\(name).caf"), bpm: nil)
    }

    func testBundledLibraryHasThemesWithDrawableTitles() throws {
        let library = MusicLibrary.load(from: repo.appendingPathComponent("Assets/Music"))
        XCTAssertFalse(library.isEmpty)
        let font = try PixelFont(json: Data(contentsOf: repo.appendingPathComponent("Assets/UI/ui.json")))
        for theme in library.themes {
            for text in [theme.title] + theme.tracks.map(\.title) {
                for character in text {
                    let key = String(character).replacingOccurrences(of: "\u{FE0F}", with: "")
                    XCTAssertNotNil(font.glyphs[key], "'\(text)' needs a glyph for '\(key)'")
                }
            }
        }
    }

    func testPlaysEveryTrackOfAThemeOnceBeforeMovingOn() {
        let a = MusicLibrary.Theme(title: "A", tracks: ["a1", "a2", "a3"].map(track))
        let b = MusicLibrary.Theme(title: "B", tracks: ["b1", "b2"].map(track))
        var rng = SystemRandomNumberGenerator()
        let random = { (n: Int) in Int.random(in: 0..<n, using: &rng) }
        var plan = RadioPlan(library: MusicLibrary(themes: [a, b]), random: random)!
        let first = plan.theme
        var played: [String] = []
        for _ in 0..<first.tracks.count { played.append(plan.next(random: random).track.title) }
        XCTAssertEqual(Set(played), Set(first.tracks.map(\.title)), "a whole theme, no repeats")

        let following = plan.next(random: random)
        XCTAssertNotEqual(following.theme, first.title, "then a different theme")
    }

    func testSingleThemeStartsOverReshuffled() {
        let only = MusicLibrary.Theme(title: "Only", tracks: ["x", "y"].map(track))
        var plan = RadioPlan(library: MusicLibrary(themes: [only]), random: { _ in 0 })!
        _ = plan.next(random: { _ in 0 })
        _ = plan.next(random: { _ in 0 })
        XCTAssertEqual(plan.next(random: { _ in 0 }).theme, "Only")
    }

    func testRandomnessDecidesThemeAndOrder() {
        let a = MusicLibrary.Theme(title: "A", tracks: ["1", "2", "3"].map(track))
        let b = MusicLibrary.Theme(title: "B", tracks: ["4"].map(track))
        let lastTheme = RadioPlan(library: MusicLibrary(themes: [a, b]), random: { $0 - 1 })!
        XCTAssertEqual(lastTheme.theme.title, "B")
        let firstTheme = RadioPlan(library: MusicLibrary(themes: [a, b]), random: { _ in 0 })!
        XCTAssertEqual(firstTheme.theme.title, "A")
        XCTAssertEqual(firstTheme.queue.map(\.title), ["2", "3", "1"], "Fisher–Yates with index 0 every time")
    }

    func testEmptyLibraryHasNoPlan() {
        XCTAssertNil(RadioPlan(library: MusicLibrary(themes: []), random: { _ in 0 }))
        XCTAssertTrue(MusicLibrary(themes: [MusicLibrary.Theme(title: "empty", tracks: [])]).isEmpty)
    }

    func testUnplugIsNotARandomAction() throws {
        let pack = try SkinPack.load(from: repo.appendingPathComponent("Assets/Skins/pibbo"))
        for system in ["unplug", "backfloat", "holdpaw", "look", "ripple"] {
            XCTAssertFalse(pack.availableActions.contains(system), system)
            XCTAssertNotEqual(pack.resolve(system).name, "chill", "\(system) is in the bundled skin")
        }
        XCTAssertEqual(pack.resolve("unplug").clip.loops, false)
    }
}
