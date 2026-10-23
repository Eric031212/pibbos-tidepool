import XCTest
@testable import Brain
import World

final class BottleTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let config = BrainConfig()

    func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    func run(_ brain: inout Brain, until time: Date) {
        while let deadline = brain.nextDeadline, deadline <= time {
            brain.handle(.timerFired, at: deadline)
        }
    }

    func testABottleDriftsInAfterAFewDaysAndOffAgainUnopened() {
        var brain = Brain(config: config, now: start, random: { $0.lowerBound })
        let arrives = at(config.bottleInterval.lowerBound)
        XCTAssertEqual(brain.nextBottle, arrives)
        run(&brain, until: arrives.addingTimeInterval(-1))
        XCTAssertFalse(brain.output.bottle)

        run(&brain, until: arrives)
        XCTAssertTrue(brain.output.bottle)
        XCTAssertEqual(brain.output.visual, .state(.hidden), "it arrives quietly; Pibbo doesn't pop up")

        let leaves = arrives.addingTimeInterval(config.bottleStay)
        run(&brain, until: leaves)
        XCTAssertFalse(brain.output.bottle)
        XCTAssertEqual(brain.nextBottle, leaves.addingTimeInterval(config.bottleInterval.lowerBound), "next one in a few days")
    }

    func testOpeningTheBottleShowsPibboReadingANote() {
        var brain = Brain(config: config, now: start, nextBottle: at(10), random: { $0.lowerBound })
        run(&brain, until: at(10))
        XCTAssertTrue(brain.output.bottle)

        brain.handle(.bottleClicked, at: at(20))
        XCTAssertFalse(brain.output.bottle)
        XCTAssertEqual(brain.output.visual, .action("note"))
        XCTAssertEqual(brain.output.bubble, .note(pick: 0))
        XCTAssertEqual(brain.nextBottle, at(20 + config.bottleInterval.lowerBound))

        run(&brain, until: at(20 + config.noteDuration))
        XCTAssertNil(brain.output.bubble)
        XCTAssertEqual(brain.output.visual, .state(.chill), "he stays out a while after reading")
    }

    func testClickingWhenNoBottleIsThereDoesNothing() {
        var brain = Brain(config: config, now: start, random: { $0.lowerBound })
        let before = brain.nextBottle
        brain.handle(.bottleClicked, at: at(1))
        XCTAssertNotEqual(brain.output.visual, .action("note"))
        XCTAssertEqual(brain.nextBottle, before)
    }

    func testTheNoteShowsEvenWhileMusicPlays() {
        var brain = Brain(config: config, now: start, nextBottle: at(10), random: { $0.lowerBound })
        brain.handle(.musicChanged(source: Brain.builtInSource, playing: true), at: at(1))
        run(&brain, until: at(10))
        brain.handle(.bottleClicked, at: at(11))
        XCTAssertEqual(brain.output.bubble, .note(pick: 0))
        XCTAssertEqual(brain.output.visual, .action("note"))
    }

    func testWorkModeKeepsBottlesAwayUntilItEnds() {
        var brain = Brain(config: config, now: start, nextBottle: at(10), random: { $0.lowerBound })
        brain.handle(.workModeEntered, at: at(1))
        run(&brain, until: at(1000))
        XCTAssertFalse(brain.output.bottle)
        XCTAssertNil(brain.nextDeadline.flatMap { $0 <= at(1000) ? $0 : nil }, "no busy timer for a due bottle")

        brain.handle(.clicked, at: at(1000))  // ends work mode
        run(&brain, until: at(1001))
        XCTAssertTrue(brain.output.bottle, "the bottle that was due drifts in afterwards")
    }

    func testABottleDueWhileAwayArrivesAtLaunch() {
        var brain = Brain(config: config, now: start, nextBottle: at(-86_400), random: { $0.lowerBound })
        XCTAssertLessThanOrEqual(brain.nextDeadline!, start, "the platform's timer fires right away...")
        brain.handle(.timerFired, at: start)  // ...at the real current time
        XCTAssertTrue(brain.output.bottle)
        run(&brain, until: at(config.bottleStay - 1))
        XCTAssertTrue(brain.output.bottle, "it stays its full time from now, not from when it was due")
    }

    func testDemoBottlesComeQuickly() {
        XCTAssertLessThan(BrainConfig.demo.bottleInterval.upperBound, 120)
    }
}
