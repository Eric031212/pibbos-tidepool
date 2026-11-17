import XCTest
@testable import Brain
import World

final class ToyAndFlipTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let config = BrainConfig()

    func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    func run(_ brain: inout Brain, until time: Date) {
        while let deadline = brain.nextDeadline, deadline <= time {
            brain.handle(.timerFired, at: deadline)
        }
    }

    /// Built-in radio playing Pixel Tide; `roll` picks themed (< 0.6) or general moves.
    private func listening(roll: Double = 0, general: [String] = MusicMoves.general) -> Brain {
        var brain = Brain(config: config, now: start, random: { range in
            range.upperBound <= 1 ? min(roll, range.upperBound) : range.lowerBound
        })
        brain.handle(.musicMovesChanged(themed: ["game"], general: general, finales: MusicMoves.finales), at: start)
        brain.handle(.musicChanged(source: Brain.builtInSource, playing: true), at: start)
        return brain
    }

    func testHePlaysTheThemesOwnMoveWithAFinale() {
        var brain = listening(roll: 0)
        XCTAssertEqual(brain.output.visual, .state(.music))
        let picksUp = at(config.toyInterval.lowerBound)
        run(&brain, until: picksUp)
        XCTAssertEqual(brain.output.visual, .action("game"))
        XCTAssertNil(brain.output.bubble)

        run(&brain, until: picksUp.addingTimeInterval(config.toyDuration - config.ggDuration))
        XCTAssertEqual(brain.output.bubble, .finale("game"), "GG at the end, even over the music")

        run(&brain, until: picksUp.addingTimeInterval(config.toyDuration))
        XCTAssertEqual(brain.output.visual, .state(.music), "back to listening")
    }

    func testGeneralMovesMixInWithoutAFinale() {
        var brain = listening(roll: 0.9)  // past the themed share: a general move
        run(&brain, until: at(config.toyInterval.lowerBound))
        guard case .action(let move) = brain.output.visual else { return XCTFail("no move") }
        XCTAssertTrue(MusicMoves.general.contains(move))
        run(&brain, until: at(config.toyInterval.lowerBound + config.toyDuration - config.ggDuration))
        XCTAssertNil(brain.output.bubble, "general moves end quietly")
    }

    func testGeneralMovesAlsoForOtherMusicButNotTheThemesOwn() {
        var brain = Brain(config: config, now: start, random: { range in range.upperBound <= 1 ? 0 : range.lowerBound })
        brain.handle(.musicMovesChanged(themed: ["game"], general: ["sway"], finales: MusicMoves.finales), at: start)
        brain.handle(.musicChanged(source: "com.apple.Music", playing: true), at: start)
        run(&brain, until: at(config.toyInterval.lowerBound))
        XCTAssertEqual(brain.output.visual, .action("sway"), "Apple Music: only general moves")
    }

    func testNoMovesWithoutMusicOrMoves() {
        var plain = Brain(config: config, now: start, random: { $0.lowerBound })
        plain.handle(.musicChanged(source: Brain.builtInSource, playing: true), at: start)
        run(&plain, until: at(config.toyInterval.upperBound * 3))
        XCTAssertEqual(plain.output.visual, .state(.music), "no moves known: just the bob")

        var silent = Brain(config: config, now: start, random: { $0.lowerBound })
        silent.handle(.musicMovesChanged(themed: [], general: ["sway"], finales: []), at: start)
        run(&silent, until: at(config.toyInterval.upperBound * 3))
        XCTAssertNotEqual(silent.output.visual, .action("sway"), "no music, no moves")
    }

    func testPickingMoves() {
        XCTAssertEqual(MusicMoves.pick(themed: ["a", "b"], general: ["x"], roll: 0.1, index: 0.7), "b")
        XCTAssertEqual(MusicMoves.pick(themed: ["a"], general: ["x", "y"], roll: 0.9, index: 0.7), "y")
        XCTAssertEqual(MusicMoves.pick(themed: [], general: ["x"], roll: 0.1, index: 0), "x")
        XCTAssertEqual(MusicMoves.pick(themed: ["a"], general: [], roll: 0.9, index: 0), "a")
        XCTAssertNil(MusicMoves.pick(themed: [], general: [], roll: 0, index: 0))
    }

    func testThreeSplashesMakeHimFlip() {
        var brain = Brain(config: config, now: start, random: { $0.lowerBound })
        brain.handle(.splashCombo, at: at(10))
        XCTAssertEqual(brain.output.visual, .action("flip"))
        run(&brain, until: at(10 + config.flipDuration))
        XCTAssertNotEqual(brain.output.visual, .action("flip"))

        brain.handle(.workModeEntered, at: at(20))
        brain.handle(.splashCombo, at: at(21))
        XCTAssertEqual(brain.output.visual, .submerged, "no flips in Dive time")
    }

    func testDriftFollowsTheSeasonButNotTheRain() {
        XCTAssertEqual(Drift.item(for: WorldContext(timeOfDay: .day, season: .spring, weather: .clear)), "spring")
        XCTAssertEqual(Drift.item(for: WorldContext(timeOfDay: .day, season: .autumn, weather: nil)), "autumn")
        XCTAssertNil(Drift.item(for: WorldContext(timeOfDay: .day, season: .winter, weather: .clear)))
        XCTAssertNil(Drift.item(for: WorldContext(timeOfDay: .day, season: .summer, weather: .rain)))
    }
}
