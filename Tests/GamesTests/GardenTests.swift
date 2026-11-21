import XCTest
@testable import Games

final class GardenRulesTests: XCTestCase {
    let clock = GardenClock()
    let start = Date(timeIntervalSince1970: 86_400 * 20_000)  // a day boundary

    func day(_ n: Double) -> Date { start.addingTimeInterval(n * 86_400) }

    func testItGrowsThroughFiveStagesWithRealDays() {
        let plot = GardenPlot(kind: .tulip, plantedAt: start)  // 4 days to bloom
        XCTAssertEqual(GardenRules.stage(plot, now: start, clock: clock), 0)
        XCTAssertEqual(GardenRules.stage(plot, now: day(1), clock: clock), 1)
        XCTAssertEqual(GardenRules.stage(plot, now: day(2), clock: clock), 2)
        XCTAssertEqual(GardenRules.stage(plot, now: day(3.5), clock: clock), 3, "a bud just before")
        XCTAssertEqual(GardenRules.stage(plot, now: day(4), clock: clock), 4)
        XCTAssertTrue(GardenRules.isInBloom(plot, now: day(40), clock: clock), "and it never wilts")
    }

    func testWateringHelpsOncePerDay() {
        var state = GardenRules.plant(.tulip, in: 0, of: GardenState(), now: start)
        var helped: Bool
        (state, helped) = GardenRules.water(0, of: state, now: start.addingTimeInterval(60), clock: clock)
        XCTAssertTrue(helped)
        (state, helped) = GardenRules.water(0, of: state, now: start.addingTimeInterval(120), clock: clock)
        XCTAssertFalse(helped, "once a day counts")
        let plot = state.plots[0]!
        XCTAssertEqual(GardenRules.growth(plot, now: day(1), clock: clock), 1 + GardenRules.waterBonus, accuracy: 0.001)
        XCTAssertTrue(GardenRules.wateredToday(plot, now: start.addingTimeInterval(3600), clock: clock))
        XCTAssertFalse(GardenRules.wateredToday(plot, now: day(1.1), clock: clock))
    }

    func testWateredDailyItBloomsSooner() {
        var state = GardenRules.plant(.sunflower, in: 2, of: GardenState(), now: start)  // 7 days
        for n in 0..<5 { state = GardenRules.water(2, of: state, now: day(Double(n) + 0.1), clock: clock).state }
        XCTAssertTrue(GardenRules.isInBloom(state.plots[2]!, now: day(5), clock: clock), "7 days of growth in 5")
        let unwatered = GardenRules.plant(.sunflower, in: 2, of: GardenState(), now: start)
        XCTAssertFalse(GardenRules.isInBloom(unwatered.plots[2]!, now: day(5), clock: clock))
    }

    func testPlantingOnlyInEmptyPlots() {
        let state = GardenRules.plant(.daisy, in: 1, of: GardenState(), now: start)
        XCTAssertEqual(state.plots[1]?.kind, .daisy)
        XCTAssertEqual(GardenRules.plant(.poppy, in: 1, of: state, now: start).plots[1]?.kind, .daisy)
        XCTAssertEqual(GardenRules.plant(.poppy, in: 9, of: state, now: start), state, "no such plot")
    }

    func testPickingABloomFillsThePotAndLeavesABud() {
        var state = GardenRules.plant(.daisy, in: 0, of: GardenState(), now: start)
        XCTAssertEqual(GardenRules.pick(0, of: state, now: day(1), clock: clock), state, "not in bloom yet")
        state = GardenRules.pick(0, of: state, now: day(3), clock: clock)
        XCTAssertEqual(state.potFlower, .daisy)
        XCTAssertEqual(state.picks, 1)
        let plot = state.plots[0]!
        XCTAssertEqual(GardenRules.stage(plot, now: day(3), clock: clock), 3, "back to a bud")
        XCTAssertTrue(GardenRules.isInBloom(plot, now: day(3 + 3 * (1 - GardenRules.regrowShare)), clock: clock), "and it blooms again soon")
    }

    func testStateSurvivesSaving() throws {
        var state = GardenRules.plant(.lavender, in: 4, of: GardenState(), now: start)
        state = GardenRules.water(4, of: state, now: start, clock: clock).state
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(GardenState.self, from: data), state)
        XCTAssertEqual(GardenState(plots: []).plots.count, GardenState.plotCount)
    }

    func testShortDaysForTheDemo() {
        let demo = GardenClock(dayLength: 30)
        let plot = GardenPlot(kind: .daisy, plantedAt: start)
        XCTAssertTrue(GardenRules.isInBloom(plot, now: start.addingTimeInterval(90), clock: demo))
    }
}

final class MemoryGardenStore: GardenStore {
    var state = GardenState()
    var saves = 0
    func load() -> GardenState { state }
    func save(_ state: GardenState) { self.state = state; saves += 1 }
}

final class GardenGameTests: XCTestCase {
    let dt = GameSession.stepLength
    var clockTime = Date(timeIntervalSince1970: 86_400 * 20_000)

    private func tap(_ game: inout GardenGame, _ x: Int, _ y: Int) {
        var input = GameInput()
        input.tap = GamePoint(x: Double(x), y: Double(y))
        game.step(input, dt: dt)
    }

    private func plotCentre(_ i: Int) -> (Int, Int) {
        let p = GardenGame.plots[i]
        return (p.x + 12, p.y + 2)
    }

    func testTapEmptyPlotThenASeedPlantsIt() {
        let store = MemoryGardenStore()
        let fixed = clockTime
        var game = GardenGame(store: store, now: { fixed })
        let (x, y) = plotCentre(0)
        tap(&game, x, y)
        XCTAssertEqual(game.picking, 0)
        XCTAssertTrue(game.scene.sprites.contains { $0.name == "panel" })
        let seed = GardenGame.seedOrigin(2)  // sunflower
        tap(&game, seed.x + 4, seed.y + 4)
        XCTAssertNil(game.picking)
        XCTAssertEqual(store.state.plots[0]?.kind, FlowerKind.allCases[2])
        XCTAssertTrue(game.scene.sprites.contains { $0.name == FlowerKind.allCases[2].rawValue })
    }

    func testATapAwayClosesThePickerWithoutPlanting() {
        let store = MemoryGardenStore()
        let fixed = clockTime
        var game = GardenGame(store: store, now: { fixed })
        let (x, y) = plotCentre(3)
        tap(&game, x, y)
        tap(&game, 2, 110)
        XCTAssertNil(game.picking)
        XCTAssertNil(store.state.plots[3])
    }

    func testTapGrowingWatersTapBloomPicks() {
        let store = MemoryGardenStore()
        store.state = GardenRules.plant(.daisy, in: 1, of: GardenState(), now: clockTime)
        var now = clockTime.addingTimeInterval(3600)
        var game = GardenGame(store: store, now: { now })
        let (x, y) = plotCentre(1)
        tap(&game, x, y)
        XCTAssertEqual(store.state.plots[1]?.wateredDays.count, 1, "watered")
        XCTAssertTrue(game.scene.texts.contains { $0.key == .splash })
        XCTAssertTrue(game.scene.sprites.contains { $0.name == "soil" && $0.frame == 1 }, "wet soil shows")

        now = clockTime.addingTimeInterval(3 * 86_400)
        tap(&game, x, y)
        XCTAssertEqual(store.state.potFlower, .daisy, "picked for the pool")
        XCTAssertTrue(game.scene.texts.contains { $0.key == .forThePool })
    }

    func testPibboWalksToThePlot() {
        let store = MemoryGardenStore()
        let fixed = clockTime
        var game = GardenGame(store: store, now: { fixed })
        let (x, y) = plotCentre(2)
        tap(&game, x, y)
        for _ in 0..<240 { game.step(GameInput(), dt: dt) }
        let pibbo = game.scene.sprites.first { $0.name == "pibbo" }!
        XCTAssertEqual(pibbo.x, GardenGame.plots[2].x - 14)
        XCTAssertFalse(game.scene.showsBest, "nothing is scored in the garden")
    }

    func testRainFallsWhenItRains() {
        let fixed = clockTime
        let game = GardenGame(store: MemoryGardenStore(), weather: "rain", now: { fixed })
        XCTAssertTrue(game.scene.sprites.contains { $0.name == "rain" })
        let dry = GardenGame(store: MemoryGardenStore(), weather: nil, now: { fixed })
        XCTAssertFalse(dry.scene.sprites.contains { $0.name == "rain" })
    }
}

final class GardenSheetTests: XCTestCase {
    func testTheSheetHasEverythingTheGardenDraws() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sheet = try GameSheet(json: Data(contentsOf: repo.appendingPathComponent("Assets/Games/games.json")))
        let names = ["background", "soil", "panel", "pibbo", "seeds", "rain", "snow"] + FlowerKind.allCases.map(\.rawValue)
        for name in names {
            XCTAssertNotNil(sheet.item(game: GardenGame.id, name: name), "garden.\(name)")
        }
        XCTAssertEqual(sheet.item(game: GardenGame.id, name: "seeds")?.frames, FlowerKind.allCases.count)
        XCTAssertEqual(sheet.item(game: GardenGame.id, name: "pibbo")?.frames, 7)
        for kind in FlowerKind.allCases {
            XCTAssertEqual(sheet.item(game: GardenGame.id, name: kind.rawValue)?.frames, GardenRules.stages)
        }
    }
}
