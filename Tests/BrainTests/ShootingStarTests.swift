import XCTest
@testable import Brain

final class ShootingStarTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let config = BrainConfig()

    func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    func run(_ brain: inout Brain, until time: Date) {
        while let deadline = brain.nextDeadline, deadline <= time {
            brain.handle(.timerFired, at: deadline)
        }
    }

    private func clearNight() -> Brain {
        var brain = Brain(config: config, now: start, random: { $0.lowerBound })
        brain.handle(.clearNightChanged(true), at: start)
        return brain
    }

    func testStarsOnlyFallOnClearNights() {
        var brain = Brain(config: config, now: start, random: { $0.lowerBound })
        run(&brain, until: at(3 * 3600))
        XCTAssertFalse(brain.output.shootingStar)

        brain.handle(.clearNightChanged(true), at: at(3 * 3600))
        let falls = at(3 * 3600 + config.shootingStarInterval.lowerBound)
        run(&brain, until: falls.addingTimeInterval(-1))
        XCTAssertFalse(brain.output.shootingStar)
        run(&brain, until: falls)
        XCTAssertTrue(brain.output.shootingStar)
    }

    func testTheWishWindowClosesOnItsOwn() {
        var brain = clearNight()
        let falls = at(config.shootingStarInterval.lowerBound)
        run(&brain, until: falls)
        XCTAssertTrue(brain.output.shootingStar)
        run(&brain, until: falls.addingTimeInterval(config.wishWindow))
        XCTAssertFalse(brain.output.shootingStar)
        XCTAssertEqual(brain.nextDeadline.map { $0 > falls }, true, "the next star is scheduled")
    }

    func testClickingInTimeMakesAWish() {
        var brain = clearNight()
        let falls = at(config.shootingStarInterval.lowerBound)
        run(&brain, until: falls)
        brain.handle(.wished, at: falls.addingTimeInterval(2))
        XCTAssertFalse(brain.output.shootingStar)
        XCTAssertEqual(brain.output.visual, .action("wish"))
        XCTAssertEqual(brain.output.bubble, .wish)

        run(&brain, until: falls.addingTimeInterval(2 + config.wishDuration))
        XCTAssertNil(brain.output.bubble)
    }

    func testAWishAfterTheWindowDoesNothing() {
        var brain = clearNight()
        brain.handle(.wished, at: at(1))
        XCTAssertNotEqual(brain.output.visual, .action("wish"))
    }

    func testCloudsStopTheStars() {
        var brain = clearNight()
        brain.handle(.clearNightChanged(false), at: at(60))
        run(&brain, until: at(5 * 3600))
        XCTAssertFalse(brain.output.shootingStar)
    }

    func testNoStarsInWorkModeOrWhileAway() {
        var busy = clearNight()
        busy.handle(.workModeEntered, at: at(1))
        run(&busy, until: at(5 * 3600))
        XCTAssertFalse(busy.output.shootingStar)

        var away = clearNight()
        away.handle(.userIdle(seconds: 3600), at: at(1))
        run(&away, until: at(config.shootingStarInterval.lowerBound))
        XCTAssertFalse(away.output.shootingStar, "nobody's watching: it goes by unseen")
    }

    func testTheWishShowsOverMusic() {
        var brain = clearNight()
        brain.handle(.musicChanged(source: Brain.builtInSource, playing: true), at: at(1))
        run(&brain, until: at(config.shootingStarInterval.lowerBound))
        brain.handle(.wished, at: at(config.shootingStarInterval.lowerBound + 1))
        XCTAssertEqual(brain.output.bubble, .wish)
    }
}
