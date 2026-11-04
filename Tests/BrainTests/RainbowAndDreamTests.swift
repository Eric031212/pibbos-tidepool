import XCTest
@testable import Brain

final class RainbowAndDreamTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let config = BrainConfig()

    func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    func run(_ brain: inout Brain, until time: Date) {
        while let deadline = brain.nextDeadline, deadline <= time {
            brain.handle(.timerFired, at: deadline)
        }
    }

    private func hidden() -> (Brain, Date) {
        var brain = Brain(config: config, now: start, random: { $0.lowerBound })
        let hid = at(config.hideAfterNoInteraction)
        run(&brain, until: hid)
        XCTAssertEqual(brain.output.visual, .state(.hidden))
        return (brain, hid)
    }

    // MARK: rainbow

    func testHeComesUpToAdmireTheRainbow() {
        var (brain, now) = hidden()
        brain.handle(.rainbowAppeared, at: now.addingTimeInterval(1))
        XCTAssertEqual(brain.output.visual, .action("admire"))
        run(&brain, until: now.addingTimeInterval(1 + config.admireDuration))
        XCTAssertEqual(brain.output.visual, .state(.hidden))
    }

    func testNoRainbowPopUpDuringACallOrMusicOrWhenAlreadyOut() {
        var (brain, now) = hidden()
        brain.handle(.callChanged(true), at: now.addingTimeInterval(1))
        brain.handle(.rainbowAppeared, at: now.addingTimeInterval(2))
        XCTAssertEqual(brain.output.visual, .submerged)

        var out = Brain(config: config, now: start, random: { $0.lowerBound })
        out.handle(.rainbowAppeared, at: at(1))
        XCTAssertEqual(out.output.visual, .state(.peek), "already out: nothing changes")
    }

    // MARK: dreams

    func testDreamsComeWhileHeSleeps() {
        var (brain, now) = hidden()
        brain.handle(.userIdle(seconds: config.idleBeforeSleep), at: now)
        XCTAssertEqual(brain.output.visual, .state(.sleep))
        let dreams = now.addingTimeInterval(config.dreamInterval.lowerBound)
        run(&brain, until: dreams.addingTimeInterval(-1))
        XCTAssertNil(brain.output.bubble)
        run(&brain, until: dreams)
        XCTAssertEqual(brain.output.bubble, .dream(pick: 0))
        run(&brain, until: dreams.addingTimeInterval(config.dreamDuration))
        XCTAssertNil(brain.output.bubble)
        XCTAssertEqual(brain.output.visual, .state(.sleep), "still asleep")
    }

    func testNoDreamsAwakeOrInWorkMode() {
        var (brain, now) = hidden()
        run(&brain, until: now.addingTimeInterval(config.dreamInterval.upperBound * 2))
        XCTAssertNotEqual(brain.output.bubble, .dream(pick: 0))

        var diver = Brain(config: config, now: start, random: { $0.lowerBound })
        diver.handle(.workModeEntered, at: at(1))
        diver.handle(.userIdle(seconds: config.idleBeforeSleep), at: at(2))
        run(&diver, until: at(config.dreamInterval.upperBound * 2))
        XCTAssertNil(diver.output.bubble)
    }

    func testWakingUpEndsTheDreams() {
        var (brain, now) = hidden()
        brain.handle(.userIdle(seconds: config.idleBeforeSleep), at: now)
        brain.handle(.userIdle(seconds: 0), at: now.addingTimeInterval(30))
        run(&brain, until: now.addingTimeInterval(config.dreamInterval.upperBound * 2))
        XCTAssertNil(brain.output.bubble)
    }
}
