import XCTest
@testable import Brain
import World

final class BrainTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let config = BrainConfig()

    func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    /// Random source that always returns the lower bound, so timings are exact.
    func makeBrain(random: @escaping (ClosedRange<Double>) -> Double = { $0.lowerBound }) -> Brain {
        Brain(config: config, now: start, random: random)
    }

    /// Fires the timer at every deadline up to `time`, like the platform would.
    func run(_ brain: inout Brain, until time: Date) {
        while let deadline = brain.nextDeadline, deadline <= time {
            brain.handle(.timerFired, at: deadline)
        }
    }

    // MARK: - Default flow

    func testLaunchPeeksThenChillsThenHides() {
        var brain = makeBrain()
        XCTAssertEqual(brain.output.visual, .state(.peek))
        XCTAssertEqual(brain.nextDeadline, at(config.launchPeek))

        run(&brain, until: at(config.launchPeek))
        XCTAssertEqual(brain.output.visual, .state(.chill))

        run(&brain, until: at(config.hideAfterNoInteraction - 1))
        XCTAssertEqual(brain.output.visual, .state(.chill))

        run(&brain, until: at(config.hideAfterNoInteraction))
        XCTAssertEqual(brain.output.visual, .state(.hidden))
    }

    func testLongGapSettlesStraightToHidden() {
        var brain = makeBrain()
        brain.handle(.timerFired, at: at(10_000))
        XCTAssertEqual(brain.output.visual, .state(.hidden))
    }

    // MARK: - Hover and click

    func testHoverRevealsFromHidden() {
        var brain = makeBrain()
        run(&brain, until: at(200))
        XCTAssertEqual(brain.output.visual, .state(.hidden))

        brain.handle(.hoverBegan, at: at(300))
        XCTAssertEqual(brain.output.visual, .state(.peek))
        run(&brain, until: at(300 + config.hoverPeek))
        XCTAssertEqual(brain.output.visual, .state(.chill))
    }

    func testStaysVisibleWhileHovering() {
        var brain = makeBrain()
        brain.handle(.hoverBegan, at: at(10))
        run(&brain, until: at(1_000))
        XCTAssertEqual(brain.output.visual, .state(.chill))

        brain.handle(.hoverEnded, at: at(1_000))
        run(&brain, until: at(1_000 + config.hideAfterNoInteraction - 1))
        XCTAssertEqual(brain.output.visual, .state(.chill))
        run(&brain, until: at(1_000 + config.hideAfterNoInteraction))
        XCTAssertEqual(brain.output.visual, .state(.hidden))
    }

    func testClickShowsChillAndRestartsTheHideTimer() {
        var brain = makeBrain()
        run(&brain, until: at(200))
        brain.handle(.clicked, at: at(300))
        XCTAssertEqual(brain.output.visual, .state(.chill))
        run(&brain, until: at(300 + config.hideAfterNoInteraction - 1))
        XCTAssertEqual(brain.output.visual, .state(.chill))
        run(&brain, until: at(300 + config.hideAfterNoInteraction))
        XCTAssertEqual(brain.output.visual, .state(.hidden))
    }

    // MARK: - Work mode

    func testWorkModeSubmergesIgnoresHoverAndEndsOnClick() {
        var brain = makeBrain()
        brain.handle(.workModeEntered, at: at(10))
        XCTAssertEqual(brain.output.visual, .submerged)
        XCTAssertTrue(brain.output.isWorkMode)
        XCTAssertNil(brain.nextDeadline, "never appears on his own in work mode")

        brain.handle(.hoverBegan, at: at(20))
        XCTAssertEqual(brain.output.visual, .submerged)

        brain.handle(.musicChanged(source: "apple-music", playing: true), at: at(30))
        XCTAssertEqual(brain.output.visual, .submerged, "work mode beats music")

        brain.handle(.clicked, at: at(40))
        XCTAssertFalse(brain.output.isWorkMode)
        XCTAssertEqual(brain.output.visual, .state(.music))
    }

    // MARK: - Music

    func testMusicOverridesAndReturnsToPreviousState() {
        var brain = makeBrain()
        run(&brain, until: at(200))
        brain.handle(.musicChanged(source: "apple-music", playing: true), at: at(300))
        XCTAssertEqual(brain.output.visual, .state(.music))

        brain.handle(.musicChanged(source: "apple-music", playing: false), at: at(400))
        XCTAssertEqual(brain.output.visual, .state(.music), "stop is debounced")
        run(&brain, until: at(400 + config.musicStopDebounce))
        XCTAssertEqual(brain.output.visual, .state(.hidden))
    }

    func testBriefStopBetweenTracksIsIgnored() {
        var brain = makeBrain()
        brain.handle(.musicChanged(source: "apple-music", playing: true), at: at(10))
        brain.handle(.musicChanged(source: "apple-music", playing: false), at: at(20))
        brain.handle(.musicChanged(source: "apple-music", playing: true), at: at(20.08))
        run(&brain, until: at(30))
        XCTAssertEqual(brain.output.visual, .state(.music))
    }

    func testMusicStopsOnlyWhenEverySourceStopped() {
        var brain = makeBrain()
        brain.handle(.musicChanged(source: "apple-music", playing: true), at: at(10))
        brain.handle(.musicChanged(source: "built-in", playing: true), at: at(11))
        brain.handle(.musicChanged(source: "apple-music", playing: false), at: at(12))
        run(&brain, until: at(20))
        XCTAssertEqual(brain.output.visual, .state(.music))
    }

    func testStopFromAnUnknownSourceIsIgnored() {
        var brain = makeBrain()
        brain.handle(.musicChanged(source: "apple-music", playing: false), at: at(1))
        XCTAssertEqual(brain.output.visual, .state(.peek))
    }

    // MARK: - Sleep

    func testIdleSleepsAndWakesQuietly() {
        var brain = makeBrain()
        brain.handle(.userIdle(seconds: config.idleBeforeSleep - 1), at: at(600))
        XCTAssertNotEqual(brain.output.visual, .state(.sleep))

        brain.handle(.userIdle(seconds: config.idleBeforeSleep), at: at(630))
        XCTAssertEqual(brain.output.visual, .state(.sleep))

        brain.handle(.userIdle(seconds: 2), at: at(660))
        XCTAssertEqual(brain.output.visual, .state(.hidden))
    }

    func testSleepsSoonerAtNight() {
        var brain = makeBrain()
        brain.handle(.timeOfDayChanged(.night), at: at(1))
        brain.handle(.userIdle(seconds: config.idleBeforeSleepAtNight), at: at(400))
        XCTAssertEqual(brain.output.visual, .state(.sleep))
    }

    func testMusicBeatsSleep() {
        var brain = makeBrain()
        brain.handle(.userIdle(seconds: config.idleBeforeSleep), at: at(600))
        brain.handle(.musicChanged(source: "apple-music", playing: true), at: at(610))
        XCTAssertEqual(brain.output.visual, .state(.music))
    }

    // MARK: - Suspension

    func testSuspensionHidesAndStopsTimersUntilEveryReasonClears() {
        var brain = makeBrain()
        brain.handle(.suspended(.fullscreen), at: at(2))
        XCTAssertTrue(brain.output.isSuspended)
        XCTAssertNil(brain.nextDeadline)

        brain.handle(.suspended(.locked), at: at(3))
        brain.handle(.resumed(.fullscreen), at: at(4))
        XCTAssertTrue(brain.output.isSuspended, "still locked")

        brain.handle(.resumed(.locked), at: at(5))
        XCTAssertFalse(brain.output.isSuspended)
        XCTAssertEqual(brain.output.visual, .state(.hidden))
        XCTAssertEqual(brain.nextDeadline, at(5 + config.randomAppearanceInterval.lowerBound))
    }

    func testResumingAnUnknownReasonDoesNothing() {
        var brain = makeBrain()
        brain.handle(.resumed(.asleep), at: at(1))
        XCTAssertEqual(brain.output.visual, .state(.peek))
    }

    func testMusicThatStoppedWhileSuspendedIsSettledOnResume() {
        var brain = makeBrain()
        brain.handle(.musicChanged(source: "apple-music", playing: true), at: at(1))
        brain.handle(.suspended(.locked), at: at(2))
        brain.handle(.musicChanged(source: "apple-music", playing: false), at: at(3))
        brain.handle(.resumed(.locked), at: at(100))
        XCTAssertEqual(brain.output.visual, .state(.hidden))
    }

    // MARK: - Random appearances

    func testRandomAppearancePlaysAnActionThenHides() {
        var brain = makeBrain()
        brain.handle(.availableActionsChanged(["stretch"]), at: at(1))
        run(&brain, until: at(config.hideAfterNoInteraction))
        XCTAssertEqual(brain.output.visual, .state(.hidden))

        let appearsAt = at(config.hideAfterNoInteraction + config.randomAppearanceInterval.lowerBound)
        XCTAssertEqual(brain.nextDeadline, appearsAt)
        run(&brain, until: appearsAt)
        XCTAssertEqual(brain.output.visual, .action("stretch"))

        run(&brain, until: appearsAt.addingTimeInterval(config.actionDuration.lowerBound))
        XCTAssertEqual(brain.output.visual, .state(.hidden))
    }

    func testRandomAppearanceWithoutActionsShowsChill() {
        var brain = makeBrain()
        let appearsAt = at(config.hideAfterNoInteraction + config.randomAppearanceInterval.lowerBound)
        run(&brain, until: appearsAt)
        XCTAssertEqual(brain.output.visual, .state(.chill))
    }

    func testNoRandomAppearanceWhileUserIsAway() {
        var brain = makeBrain()
        run(&brain, until: at(config.hideAfterNoInteraction))
        brain.handle(.userIdle(seconds: config.idleBeforeSleep), at: at(1_000))
        let appearsAt = at(config.hideAfterNoInteraction + config.randomAppearanceInterval.lowerBound)
        run(&brain, until: appearsAt)
        XCTAssertEqual(brain.output.visual, .state(.sleep))
        XCTAssertGreaterThan(brain.nextDeadline!, appearsAt, "rescheduled instead")
    }

    func testRandomIntervalComesFromInjectedRandomness() {
        var brain = makeBrain(random: { $0.upperBound })
        run(&brain, until: at(config.hideAfterNoInteraction))
        XCTAssertEqual(brain.nextDeadline, at(config.hideAfterNoInteraction + config.randomAppearanceInterval.upperBound))
    }

    // MARK: - Small actions while out

    func testDoesSmallActionsWhileChilling() {
        var brain = makeBrain()
        brain.handle(.availableActionsChanged(["water"]), at: at(1))
        run(&brain, until: at(config.launchPeek))
        XCTAssertEqual(brain.output.visual, .state(.chill))

        let actionAt = at(config.launchPeek + config.chillActionInterval.lowerBound)
        run(&brain, until: actionAt)
        XCTAssertEqual(brain.output.visual, .action("water"))

        run(&brain, until: actionAt.addingTimeInterval(config.actionDuration.lowerBound))
        XCTAssertEqual(brain.output.visual, .state(.chill), "back to chill after the action")
    }

    func testSmallActionStopsWhenPibboHides() {
        var brain = makeBrain()
        brain.handle(.availableActionsChanged(["water"]), at: at(1))
        run(&brain, until: at(config.hideAfterNoInteraction))
        XCTAssertEqual(brain.output.visual, .state(.hidden))
    }

    // MARK: - Music invitation

    func appearanceTime() -> Date {
        at(config.hideAfterNoInteraction + config.randomAppearanceInterval.lowerBound)
    }

    func testInvitesToMusicOnARandomAppearance() {
        var brain = makeBrain()
        brain.handle(.builtInMusicAvailable(true), at: at(1))
        run(&brain, until: appearanceTime())
        XCTAssertEqual(brain.output.bubble, .musicInvitation)

        run(&brain, until: appearanceTime().addingTimeInterval(config.bubbleDuration))
        XCTAssertNil(brain.output.bubble, "bubble times out")
        XCTAssertEqual(brain.output.visual, .state(.hidden), "Pibbo stayed out as long as the bubble")
    }

    func testNoInvitationWithoutBuiltInTracks() {
        var brain = makeBrain()
        run(&brain, until: appearanceTime())
        XCTAssertNil(brain.output.bubble)
    }

    func testNoInvitationWhileMusicPlays() {
        var brain = makeBrain()
        brain.handle(.builtInMusicAvailable(true), at: at(1))
        brain.handle(.musicChanged(source: "apple-music", playing: true), at: at(2))
        run(&brain, until: appearanceTime() + 3600)
        XCTAssertNil(brain.output.bubble)
    }

    func testInvitationRespectsChanceAndCooldown() {
        var config = BrainConfig()
        config.randomAppearanceInterval = 600...600
        config.musicInvitationChance = 1
        var brain = Brain(config: config, now: start, random: { $0.lowerBound })
        brain.handle(.builtInMusicAvailable(true), at: at(1))
        var invitations = 0
        var lastBubble: Bubble?
        var t = start
        while t < at(2 * 3600) {
            guard let deadline = brain.nextDeadline else { break }
            t = deadline
            brain.handle(.timerFired, at: t)
            if brain.output.bubble != nil && lastBubble == nil { invitations += 1 }
            lastBubble = brain.output.bubble
        }
        XCTAssertEqual(invitations, 2, "appearances every ~10 min, but at most one invitation per hour")

        var never = BrainConfig()
        never.musicInvitationChance = 0
        var shy = Brain(config: never, now: start, random: { $0.lowerBound })
        shy.handle(.builtInMusicAvailable(true), at: at(1))
        run(&shy, until: appearanceTime())
        XCTAssertNil(shy.output.bubble)
    }

    func testClickingTheBubbleOrStartingMusicClearsIt() {
        var brain = makeBrain()
        brain.handle(.builtInMusicAvailable(true), at: at(1))
        run(&brain, until: appearanceTime())
        brain.handle(.bubbleClicked, at: appearanceTime() + 1)
        XCTAssertNil(brain.output.bubble)

        var other = makeBrain()
        other.handle(.builtInMusicAvailable(true), at: at(1))
        run(&other, until: appearanceTime())
        other.handle(.musicChanged(source: "built-in", playing: true), at: appearanceTime() + 1)
        XCTAssertNil(other.output.bubble)
        XCTAssertEqual(other.output.visual, .state(.music))
    }

    func testClickingPibboReplacesTheBubbleWithTheMenu() {
        var brain = makeBrain()
        brain.handle(.builtInMusicAvailable(true), at: at(1))
        run(&brain, until: appearanceTime())
        brain.handle(.clicked, at: appearanceTime() + 1)
        XCTAssertNil(brain.output.bubble)
    }

    func testDemoConfigIsFaster() {
        let demo = BrainConfig.demo
        XCTAssertLessThan(demo.randomAppearanceInterval.upperBound, BrainConfig().randomAppearanceInterval.lowerBound)
        XCTAssertEqual(demo.musicInvitationChance, 1)
    }
}
