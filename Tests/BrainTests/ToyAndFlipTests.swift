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

    private func listening() -> Brain {
        var brain = Brain(config: config, now: start, random: { $0.lowerBound })
        brain.handle(.musicChanged(source: Brain.builtInSource, playing: true), at: start)
        brain.handle(.radioToyChanged("game"), at: start)
        return brain
    }

    func testHePlaysTheHandheldWhilePixelTidePlays() {
        var brain = listening()
        XCTAssertEqual(brain.output.visual, .state(.music))
        let picksUp = at(config.toyInterval.lowerBound)
        run(&brain, until: picksUp)
        XCTAssertEqual(brain.output.visual, .action("game"))
        XCTAssertNil(brain.output.bubble)

        run(&brain, until: picksUp.addingTimeInterval(config.toyDuration - config.ggDuration))
        XCTAssertEqual(brain.output.bubble, .gg, "GG at the end, even over the music")

        run(&brain, until: picksUp.addingTimeInterval(config.toyDuration))
        XCTAssertEqual(brain.output.visual, .state(.music), "back to listening")
    }

    func testNoGameWithoutTheToyOrTheRadio() {
        var plain = Brain(config: config, now: start, random: { $0.lowerBound })
        plain.handle(.musicChanged(source: Brain.builtInSource, playing: true), at: start)
        run(&plain, until: at(config.toyInterval.upperBound * 3))
        XCTAssertEqual(plain.output.visual, .state(.music))

        var stopped = listening()
        stopped.handle(.radioToyChanged(nil), at: at(1))
        run(&stopped, until: at(config.toyInterval.upperBound * 3))
        XCTAssertNotEqual(stopped.output.visual, .action("game"))
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
