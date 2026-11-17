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

final class CallPeekTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let config = BrainConfig()
    func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    func testAClickDuringACallBringsHimUpToWhisperThenDown() {
        var brain = Brain(config: config, now: start, random: { $0.lowerBound })
        brain.handle(.callChanged(true), at: at(1))
        XCTAssertEqual(brain.output.visual, .submerged)
        brain.handle(.peekedDuringCall, at: at(10))
        XCTAssertEqual(brain.output.visual, .state(.peek))
        XCTAssertEqual(brain.output.bubble, .shh)
        XCTAssertEqual(brain.nextDeadline, at(10 + config.callPeekDuration))
        brain.handle(.timerFired, at: at(10 + config.callPeekDuration))
        XCTAssertEqual(brain.output.visual, .submerged, "back down by himself")
        XCTAssertNil(brain.output.bubble)
    }

    func testNoPeekOutsideACallOrInDiveTime() {
        var brain = Brain(config: config, now: start, random: { $0.lowerBound })
        brain.handle(.peekedDuringCall, at: at(5))
        XCTAssertNotEqual(brain.output.bubble, .shh)

        brain.handle(.workModeEntered, at: at(6))
        brain.handle(.callChanged(true), at: at(7))
        brain.handle(.peekedDuringCall, at: at(8))
        XCTAssertEqual(brain.output.visual, .submerged, "Dive time stays down")
    }

    func testTheCallEndingEndsThePeek() {
        var brain = Brain(config: config, now: start, random: { $0.lowerBound })
        brain.handle(.callChanged(true), at: at(1))
        brain.handle(.peekedDuringCall, at: at(2))
        brain.handle(.callChanged(false), at: at(3))
        XCTAssertNil(brain.output.bubble)
        XCTAssertEqual(brain.output.visual, .state(.hidden))
    }
}
