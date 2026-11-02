import XCTest
@testable import Brain

final class CallTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let config = BrainConfig()

    func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    func run(_ brain: inout Brain, until time: Date) {
        while let deadline = brain.nextDeadline, deadline <= time {
            brain.handle(.timerFired, at: deadline)
        }
    }

    func testPibboDivesDuringACallAndStaysDown() {
        var brain = Brain(config: config, now: start, random: { $0.lowerBound })
        XCTAssertEqual(brain.output.visual, .state(.peek))
        brain.handle(.callChanged(true), at: at(1))
        XCTAssertEqual(brain.output.visual, .submerged)
        XCTAssertFalse(brain.output.isWorkMode, "a call is not the user's work mode")

        brain.handle(.hoverBegan, at: at(2))
        brain.handle(.rubbed, at: at(3))
        run(&brain, until: at(3 * 3600))
        XCTAssertEqual(brain.output.visual, .submerged, "no hover, play or random appearances during a call")
        XCTAssertNil(brain.output.bubble)
    }

    func testAfterTheCallHeResurfacesQuietly() {
        var brain = Brain(config: config, now: start, random: { $0.lowerBound })
        brain.handle(.callChanged(true), at: at(1))
        brain.handle(.callChanged(false), at: at(600))
        XCTAssertEqual(brain.output.visual, .state(.hidden), "back to hidden, not popping up")
        XCTAssertEqual(brain.nextDeadline, at(600 + config.randomAppearanceInterval.lowerBound))
    }

    func testNoBubblesBottlesOrStarsDuringACall() {
        var brain = Brain(config: config, now: start, nextBottle: at(100), random: { $0.lowerBound })
        brain.handle(.clearNightChanged(true), at: start)
        brain.handle(.callChanged(true), at: at(1))
        run(&brain, until: at(config.shootingStarInterval.upperBound * 2))
        XCTAssertFalse(brain.output.bottle)
        XCTAssertFalse(brain.output.shootingStar)
        XCTAssertNil(brain.nextDeadline.flatMap { $0 <= at(config.shootingStarInterval.upperBound * 2) ? $0 : nil },
                     "nothing due keeps a busy timer running")

        let end = at(config.shootingStarInterval.upperBound * 2)
        brain.handle(.callChanged(false), at: end)
        XCTAssertLessThanOrEqual(brain.nextDeadline!, end, "the overdue bottle is due right away...")
        brain.handle(.timerFired, at: end.addingTimeInterval(1))  // ...and the timer fires at the real time
        XCTAssertTrue(brain.output.bottle, "the bottle that came during the call waits for him")
    }

    func testMusicDuringACallStaysUnderWater() {
        var brain = Brain(config: config, now: start, random: { $0.lowerBound })
        brain.handle(.callChanged(true), at: at(1))
        brain.handle(.musicChanged(source: "com.apple.Music", playing: true), at: at(2))
        XCTAssertEqual(brain.output.visual, .submerged)
    }

    func testRepeatedSignalsChangeNothing() {
        var brain = Brain(config: config, now: start, random: { $0.lowerBound })
        brain.handle(.callChanged(false), at: at(1))
        XCTAssertEqual(brain.output.visual, .state(.peek), "a 'not in a call' at launch doesn't hide him")
    }
}
