import XCTest
@testable import Brain

final class GameTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let config = BrainConfig()

    func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    func run(_ brain: inout Brain, until time: Date) {
        while let deadline = brain.nextDeadline, deadline <= time {
            brain.handle(.timerFired, at: deadline)
        }
    }

    func testHePlaysAlongWhileAGameIsOpenAndNothingElseHappens() {
        var brain = Brain(config: config, now: start, nextBottle: at(100), random: { $0.lowerBound })
        brain.handle(.clearNightChanged(true), at: start)
        brain.handle(.builtInMusicAvailable(true), at: start)
        brain.handle(.visitorsChanged(["crab"], durations: ["crab": 5]), at: start)
        brain.handle(.gameChanged(true), at: at(1))
        XCTAssertEqual(brain.output.visual, .action("game"))

        brain.handle(.hoverBegan, at: at(2))
        brain.handle(.rubbed, at: at(3))
        brain.handle(.splashCombo, at: at(4))
        run(&brain, until: at(3 * 3600))
        XCTAssertEqual(brain.output.visual, .action("game"), "no hover, play or appearances during a game")
        XCTAssertNil(brain.output.bubble)
        XCTAssertFalse(brain.output.bottle)
        XCTAssertFalse(brain.output.shootingStar)
        XCTAssertNil(brain.output.visitor)
    }

    func testHePlaysAlongOverMusicToo() {
        var brain = Brain(config: config, now: start, random: { $0.lowerBound })
        brain.handle(.musicChanged(source: Brain.builtInSource, playing: true), at: at(1))
        brain.handle(.builtInTrackStarted, at: at(1))
        brain.handle(.gameChanged(true), at: at(2))
        XCTAssertEqual(brain.output.visual, .action("game"))
        XCTAssertNil(brain.output.bubble, "no now-playing bubble during a game")
    }

    func testAfterTheGameHeStaysOutAWhile() {
        var brain = Brain(config: config, now: start, random: { $0.lowerBound })
        brain.handle(.gameChanged(true), at: at(1))
        brain.handle(.gameChanged(false), at: at(300))
        XCTAssertEqual(brain.output.visual, .state(.chill))
        run(&brain, until: at(300 + config.hideAfterNoInteraction))
        XCTAssertEqual(brain.output.visual, .state(.hidden))
    }

    func testACallDuringAGameStillMeansDiving() {
        var brain = Brain(config: config, now: start, random: { $0.lowerBound })
        brain.handle(.gameChanged(true), at: at(1))
        brain.handle(.callChanged(true), at: at(2))
        XCTAssertEqual(brain.output.visual, .submerged)
        brain.handle(.callChanged(false), at: at(60))
        XCTAssertEqual(brain.output.visual, .action("game"), "the game is still open")
        brain.handle(.gameChanged(true), at: at(61))  // a repeat changes nothing
        XCTAssertEqual(brain.output.visual, .action("game"))
    }

    func testClosingWhileSuspendedStaysHidden() {
        var brain = Brain(config: config, now: start, random: { $0.lowerBound })
        brain.handle(.gameChanged(true), at: at(1))
        brain.handle(.suspended(.locked), at: at(2))
        brain.handle(.gameChanged(false), at: at(2))
        brain.handle(.resumed(.locked), at: at(30))
        XCTAssertEqual(brain.output.visual, .state(.hidden))
    }
}

final class GreetingBrainTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let config = BrainConfig()

    func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func hiddenBrain() -> Brain {
        var brain = Brain(config: config, now: start, random: { $0.lowerBound })
        while let deadline = brain.nextDeadline, deadline <= at(400) { brain.handle(.timerFired, at: deadline) }
        return brain
    }

    func testHeComesOutToGreetYouThenHides() {
        var brain = hiddenBrain()
        XCTAssertEqual(brain.output.visual, .state(.hidden))
        brain.handle(.greeted(.morning(.clear)), at: at(500))
        XCTAssertEqual(brain.output.visual, .state(.chill))
        XCTAssertEqual(brain.output.bubble, .greeting(.morning(.clear)))
        brain.handle(.timerFired, at: at(500 + config.greetingDuration))
        XCTAssertNil(brain.output.bubble)
        XCTAssertEqual(brain.output.visual, .state(.hidden))
    }

    func testTheNightOwlBringsCocoaAndShowsOverMusic() {
        var brain = hiddenBrain()
        brain.handle(.musicChanged(source: "music", playing: true), at: at(450))
        brain.handle(.greeted(.nightOwl), at: at(500))
        XCTAssertEqual(brain.output.bubble, .greeting(.nightOwl))
    }

    func testNoGreetingsWhileQuiet() {
        for quiet in [BrainEvent.workModeEntered, .callChanged(true), .gameChanged(true), .suspended(.fullscreen)] {
            var brain = hiddenBrain()
            brain.handle(quiet, at: at(450))
            brain.handle(.greeted(.welcomeBack), at: at(500))
            XCTAssertNil(brain.output.bubble, "\(quiet)")
        }
    }
}
