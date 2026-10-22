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

final class BeatGridTests: XCTestCase {
    func testFoldsTempoIntoNoddingRange() throws {
        XCTAssertEqual(try XCTUnwrap(BeatGrid(bpm: 78, offset: 0.5)).bpm, 78)
        XCTAssertEqual(try XCTUnwrap(BeatGrid(bpm: 120, offset: 0)).bpm, 60, "double-time estimate is halved")
        XCTAssertEqual(try XCTUnwrap(BeatGrid(bpm: 40, offset: 0)).bpm, 80)
        XCTAssertNil(BeatGrid(bpm: nil, offset: 0))
        XCTAssertNil(BeatGrid(bpm: 0, offset: 0))
        XCTAssertEqual(BeatGrid(bpm: 60, offset: nil)?.offset, 0)
    }

    func testPhaseLandsOnBeats() throws {
        let grid = try XCTUnwrap(BeatGrid(bpm: 60, offset: 0.5))  // a beat every second
        XCTAssertEqual(grid.phase(at: 0.5, beats: 2), 0, accuracy: 1e-9, "first beat")
        XCTAssertEqual(grid.phase(at: 2.5, beats: 2), 0, accuracy: 1e-9, "two beats later: loop restarts")
        XCTAssertEqual(grid.phase(at: 1.75, beats: 2), 1.25, accuracy: 1e-9)
        XCTAssertEqual(grid.phase(at: 0.25, beats: 2), 1.75, accuracy: 1e-9, "before the first beat")
    }
}

final class ThemePropTests: XCTestCase {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func testEveryBundledThemeNamesAPropTheSkinHas() throws {
        let library = MusicLibrary.load(from: repo.appendingPathComponent("Assets/Music"))
        let pack = try SkinPack.load(from: repo.appendingPathComponent("Assets/Skins/pibbo"))
        XCTAssertEqual(library.themes.count, 3)
        for theme in library.themes {
            let prop = try XCTUnwrap(theme.prop, theme.title)
            XCTAssertNotNil(pack.prop(named: prop), "\(theme.title): skin has no prop \(prop)")
        }
        XCTAssertEqual(Set(library.themes.compactMap(\.prop)).count, 3, "each theme has its own prop")
    }

    func testUnknownOrMissingPropShowsNothing() throws {
        let pack = try SkinPack.load(from: repo.appendingPathComponent("Assets/Skins/pibbo"))
        XCTAssertNil(pack.prop(named: nil))
        XCTAssertNil(pack.prop(named: "jukebox"))
        let clip = Clip(row: 0, frames: 2, fps: 2)
        let bare = SkinManifest(id: "t", name: "t", author: "t", version: "1", type: "skin", frameSize: 16,
                                states: Dictionary(uniqueKeysWithValues: SkinPack.requiredStates.map { ($0, clip) }),
                                actions: nil, props: ["streetlamp": clip])
        XCTAssertNil(try SkinPack(manifest: bare, directory: repo).prop(named: "streetlamp"), "no garden, no prop")
    }
}
