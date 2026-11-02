import XCTest
@testable import Brain

final class VisitorTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let config = BrainConfig()

    func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    func run(_ brain: inout Brain, until time: Date) {
        while let deadline = brain.nextDeadline, deadline <= time {
            brain.handle(.timerFired, at: deadline)
        }
    }

    /// Launch, let Pibbo hide, and stop just before his first own appearance.
    private func hiddenBrain(random: @escaping (ClosedRange<Double>) -> Double = { $0.lowerBound }) -> (Brain, Date) {
        var brain = Brain(config: config, now: start, random: random)
        brain.handle(.visitorsChanged(["crab", "friend"], durations: ["crab": 5.5, "friend": 14]), at: start)
        let appears = at(config.hideAfterNoInteraction + config.randomAppearanceInterval.lowerBound)
        run(&brain, until: appears.addingTimeInterval(-1))
        XCTAssertEqual(brain.output.visual, .state(.hidden))
        return (brain, appears)
    }

    func testAnAppearanceCanBringAVisitor() {
        var (brain, appears) = hiddenBrain()
        run(&brain, until: appears)
        XCTAssertEqual(brain.output.visitor, "crab")
        XCTAssertEqual(brain.output.visual, .action("look"), "Pibbo watches the crab")
        XCTAssertNil(brain.output.bubble, "no music invitation during a visit")

        run(&brain, until: appears.addingTimeInterval(5.5 + config.visitorLinger))
        XCTAssertNil(brain.output.visitor)
        XCTAssertEqual(brain.output.visual, .state(.hidden), "he stays out for the whole visit, then hides")
    }

    func testPibboHoldsPawsWithHisFriend() {
        // Lower bounds everywhere, except that the visitor pick (the second
        // 0...1 draw, after the visit chance) takes the last visitor: the friend.
        var unitDraws = 0
        var (brain, appears) = hiddenBrain(random: { range in
            guard range == 0...1 else { return range.lowerBound }
            unitDraws += 1
            return unitDraws % 2 == 0 ? 1 : 0
        })
        run(&brain, until: appears)
        XCTAssertEqual(brain.output.visitor, "friend")
        XCTAssertEqual(brain.output.visual, .action("friendpaw"))
    }

    func testWithoutVisitorsAppearancesAreAsBefore() {
        var brain = Brain(config: config, now: start, random: { $0.lowerBound })
        let appears = at(config.hideAfterNoInteraction + config.randomAppearanceInterval.lowerBound)
        run(&brain, until: appears)
        XCTAssertNil(brain.output.visitor)
    }

    func testHoveringDuringAVisitEndsItForBrain() {
        var (brain, appears) = hiddenBrain()
        run(&brain, until: appears)
        brain.handle(.hoverBegan, at: appears.addingTimeInterval(1))
        XCTAssertNil(brain.output.visitor, "the platform lets the visit play out; Brain moves on")
    }

    func testNoVisitorsDuringACall() {
        var (brain, appears) = hiddenBrain()
        brain.handle(.callChanged(true), at: appears.addingTimeInterval(-0.5))
        run(&brain, until: appears.addingTimeInterval(60))
        XCTAssertNil(brain.output.visitor)
    }
}
