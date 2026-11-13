import XCTest
@testable import Games

/// A scripted game: ends the round with `finalScore` after `roundSteps` steps.
private struct ScriptedGame: Game {
    var score = 0
    var phase: GamePhase = .ready
    var scene: GameScene { GameScene() }
    var finalScore: Int
    var roundSteps = 3
    var steps = 0
    var inputs: [GameInput] = []

    mutating func step(_ input: GameInput, dt: Double) {
        inputs.append(input)
        switch phase {
        case .ready, .over:
            if input.pressed { phase = .playing; steps = 0; score = 0 }
        case .playing:
            steps += 1
            if steps >= roundSteps { score = finalScore; phase = .over }
        }
    }
}

final class GameSessionTests: XCTestCase {
    private let step = GameSession.stepLength

    func testStepsAtAFixedRateWhateverTheFrames() {
        var session = GameSession(game: ScriptedGame(finalScore: 0), best: 0)
        XCTAssertEqual(session.advance(by: step * 0.5), 0)  // not a whole step yet
        XCTAssertEqual(session.advance(by: step * 0.6), 1)  // the leftover carries over
        XCTAssertEqual(session.advance(by: step * 2), 2)
    }

    func testAHitchIsCappedInsteadOfJumpingAhead() {
        var session = GameSession(game: ScriptedGame(finalScore: 0), best: 0)
        XCTAssertEqual(session.advance(by: 2), GameSession.maxStepsPerFrame)
        XCTAssertEqual(session.advance(by: step * 0.5), 0)  // the backlog was dropped
    }

    func testPressesReachExactlyOneStepButHeldKeysStay() {
        var session = GameSession(game: ScriptedGame(finalScore: 0), best: 0)
        var input = GameInput()
        input.pressed = true
        input.left = true
        input.swipe = 3
        session.receive(input)
        session.advance(by: step * 3)
        let seen = (session.game as! ScriptedGame).inputs
        XCTAssertEqual(seen.map(\.pressed), [true, false, false])
        XCTAssertEqual(seen.map(\.swipe), [3, 0, 0])
        XCTAssertEqual(seen.map(\.left), [true, true, true])
    }

    func testInputBetweenStepsAddsUp() {
        var session = GameSession(game: ScriptedGame(finalScore: 0), best: 0)
        var a = GameInput()
        a.swipe = 2
        a.pressed = true
        var b = GameInput()
        b.swipe = 1.5
        b.pointerX = 40
        session.receive(a)
        session.receive(b)
        session.advance(by: step)
        let seen = (session.game as! ScriptedGame).inputs[0]
        XCTAssertEqual(seen.swipe, 3.5)
        XCTAssertTrue(seen.pressed)
        XCTAssertEqual(seen.pointerX, 40)
    }

    func testPausedSessionsDoNothingAndForgetHeldKeys() {
        var session = GameSession(game: ScriptedGame(finalScore: 0), best: 0)
        var input = GameInput()
        input.right = true
        session.receive(input)
        session.pause()
        XCTAssertEqual(session.advance(by: 1), 0)
        session.resume()
        session.advance(by: step)
        XCTAssertFalse((session.game as! ScriptedGame).inputs[0].right)  // released while away
    }

    func testABetterRoundBecomesTheBest() {
        var session = GameSession(game: ScriptedGame(finalScore: 12), best: 10)
        var press = GameInput()
        press.pressed = true
        session.receive(press)
        session.advance(by: step * 4)  // start + 3 steps of play
        XCTAssertEqual(session.game.phase, .over)
        XCTAssertEqual(session.best, 12)
        XCTAssertTrue(session.isNewBest)

        session.receive(press)  // another round: the flag clears
        session.advance(by: step)
        XCTAssertFalse(session.isNewBest)
        XCTAssertEqual(session.best, 12)
    }

    func testAWorseRoundKeepsTheBest() {
        var session = GameSession(game: ScriptedGame(finalScore: 4), best: 10)
        var press = GameInput()
        press.pressed = true
        session.receive(press)
        session.advance(by: step * 4)
        XCTAssertEqual(session.best, 10)
        XCTAssertFalse(session.isNewBest)
    }
}

final class ShellCatchTests: XCTestCase {
    private let dt = GameSession.stepLength

    private func steps(_ game: inout ShellCatch, _ n: Int, _ input: GameInput = GameInput()) {
        for _ in 0..<n { game.step(input, dt: dt) }
    }

    func testStartsReadyInTheMiddleAndAClickStarts() {
        var game = ShellCatch(random: { $0.lowerBound })
        XCTAssertEqual(game.phase, .ready)
        XCTAssertEqual(game.pibboX, Double(Playfield.width - ShellCatch.pibboWidth) / 2)
        var press = GameInput()
        press.pressed = true
        game.step(press, dt: dt)
        XCTAssertEqual(game.phase, .playing)
    }

    func testKeysMoveHimAndTheEdgesStopHim() {
        var game = ShellCatch()
        let start = game.pibboX
        var right = GameInput()
        right.right = true
        steps(&game, 30, right)  // half a second
        XCTAssertEqual(game.pibboX, start + ShellCatch.keySpeed / 2, accuracy: 0.001)
        steps(&game, 120, right)
        XCTAssertEqual(game.pibboX, ShellCatch.maxX)
        var left = GameInput()
        left.left = true
        steps(&game, 600, left)
        XCTAssertEqual(game.pibboX, 0)
    }

    func testBothKeysCancelOut() {
        var game = ShellCatch()
        let start = game.pibboX
        var both = GameInput()
        both.left = true
        both.right = true
        steps(&game, 30, both)
        XCTAssertEqual(game.pibboX, start)
    }

    func testASwipeMovesHimByItsLength() {
        var game = ShellCatch()
        let start = game.pibboX
        var swipe = GameInput()
        swipe.swipe = -12
        game.step(swipe, dt: dt)
        XCTAssertEqual(game.pibboX, start - 12)
    }

    func testHeGlidesToThePointerAtLimitedSpeedAndStaysThere() {
        var game = ShellCatch()
        var point = GameInput()
        point.pointerX = 20  // centre him on x = 20
        game.step(point, dt: dt)
        XCTAssertLessThan(game.pibboX, Double(Playfield.width) / 2)
        XCTAssertGreaterThan(game.pibboX, 20)  // not there in one step
        steps(&game, 120)  // the target holds without new pointer moves
        XCTAssertEqual(game.pibboX, 20 - Double(ShellCatch.pibboWidth) / 2, accuracy: 0.001)
    }

    func testAKeyTakesOverFromThePointer() {
        var game = ShellCatch()
        var point = GameInput()
        point.pointerX = 0
        game.step(point, dt: dt)
        var right = GameInput()
        right.right = true
        game.step(right, dt: dt)
        let afterKey = game.pibboX
        steps(&game, 30)  // no glide back toward the old pointer target
        XCTAssertEqual(game.pibboX, afterKey)
    }

    func testSceneShowsPibboAndTheRightTexts() {
        var game = ShellCatch()
        XCTAssertEqual(game.scene.background, "background")
        XCTAssertEqual(game.scene.sprites.first?.name, "pibbo")
        XCTAssertTrue(game.scene.texts.contains { $0.key == .clickToPlay })
        var press = GameInput()
        press.pressed = true
        game.step(press, dt: dt)
        XCTAssertTrue(game.scene.texts.contains { $0.key == .score(0) })
        XCTAssertFalse(game.scene.texts.contains { $0.key == .clickToPlay })
    }
}

final class ShellCatchRoundTests: XCTestCase {
    private let dt = GameSession.stepLength

    /// A random source that returns scripted values in turn, round and round.
    private final class Script {
        let values: [Double]
        var index = 0
        init(_ values: [Double]) { self.values = values }
        func next(_ range: ClosedRange<Double>) -> Double {
            let value = values[index % values.count]
            index += 1
            return range.lowerBound + (range.upperBound - range.lowerBound) * value
        }
    }

    private func started(_ script: Script) -> ShellCatch {
        var game = ShellCatch(random: script.next)
        var press = GameInput()
        press.pressed = true
        game.step(press, dt: dt)
        return game
    }

    private func run(_ game: inout ShellCatch, seconds: Double, _ input: GameInput = GameInput()) {
        for _ in 0..<Int((seconds / dt).rounded()) { game.step(input, dt: dt) }
    }

    /// Script values: kind roll, x, speed jitter, interval jitter, repeating.
    /// Kind roll 0 → shell; x 0.5 → middle of the field (where Pibbo starts).
    func testThingsFallAndHeCatchesThemWhereHeIs() {
        var game = started(Script([0, 0.5, 0.5, 0.5]))
        run(&game, seconds: 0.7)
        XCTAssertEqual(game.items.count, 1)
        XCTAssertEqual(game.items.first?.kind, .shell)
        run(&game, seconds: 4)
        XCTAssertGreaterThanOrEqual(game.score, 1, "a shell falling onto him counts")
    }

    func testMissedThingsSplashAndCostNothing() {
        var game = started(Script([0, 0.0, 0.5, 0.5]))  // far left
        var right = GameInput()
        right.right = true
        run(&game, seconds: 4, right)  // he swims to the far right
        XCTAssertEqual(game.score, 0)
        XCTAssertTrue(game.items.allSatisfy { $0.y + Double(ShellCatch.itemSize) < Double(ShellCatch.waterLine) })
    }

    func testAJellyfishMakesHimDizzyButCostsNothing() {
        // A jellyfish in the middle (roll near the top of the weights), then a shell far left, in turn.
        var game = started(Script([0.99, 0.5, 0.5, 0.5, 0, 0, 0.5, 0.5]))
        run(&game, seconds: 0.7)
        XCTAssertEqual(game.items.first?.kind, .jelly)
        var sawDizzy = false
        for _ in 0..<600 {
            game.step(GameInput(), dt: dt)
            if game.dizzy > 0 { sawDizzy = true; break }
        }
        XCTAssertTrue(sawDizzy)
        XCTAssertEqual(game.score, 0)
        XCTAssertTrue(game.scene.sprites.contains { $0.name == "dizzy" })

        let x = game.pibboX
        var left = GameInput()
        left.left = true
        game.step(left, dt: dt)
        XCTAssertEqual(game.pibboX, x, "dizzy: he can't move")
        run(&game, seconds: ShellCatch.dizzyLength, left)
        XCTAssertLessThan(game.pibboX, x, "and swims again afterwards")
    }

    func testPointsByKind() {
        XCTAssertEqual(ShellCatch.Kind.shell.points, 1)
        XCTAssertEqual(ShellCatch.Kind.starfish.points, 2)
        XCTAssertEqual(ShellCatch.Kind.fish.points, 3)
        XCTAssertEqual(ShellCatch.Kind.jelly.points, 0)
    }

    func testARoundLastsAMinuteAndGetsFaster() {
        var game = started(Script([0.0, 0.0, 0.5, 0.5]))
        run(&game, seconds: 1)
        let earlySpeed = game.items.last?.speed ?? 0
        XCTAssertEqual(game.secondsLeft, 59)
        run(&game, seconds: 57)
        let lateSpeed = game.items.last?.speed ?? 0
        XCTAssertGreaterThan(lateSpeed, earlySpeed * 1.5)
        XCTAssertEqual(game.phase, .playing)
        run(&game, seconds: 2.1)
        XCTAssertEqual(game.phase, .over)
        XCTAssertTrue(game.items.isEmpty)
        XCTAssertTrue(game.scene.texts.contains { $0.key == .timeUp })
    }

    func testNoAccidentalRestartRightAfterTheRound() {
        var game = started(Script([0.0, 0.0, 0.5, 0.5]))
        run(&game, seconds: 60.1)
        XCTAssertEqual(game.phase, .over)
        var press = GameInput()
        press.pressed = true
        game.step(press, dt: dt)
        XCTAssertEqual(game.phase, .over, "a click just after the end doesn't restart")
        XCTAssertFalse(game.scene.texts.contains { $0.key == .clickToPlay })
        run(&game, seconds: ShellCatch.restartDelay)
        XCTAssertTrue(game.scene.texts.contains { $0.key == .clickToPlay })
        game.step(press, dt: dt)
        XCTAssertEqual(game.phase, .playing)
        XCTAssertEqual(game.score, 0)
        XCTAssertEqual(game.secondsLeft, 60)
    }

    func testTheBestScoreFollowsAFullRound() {
        // Everything falls in the middle onto Pibbo: he catches a lot.
        var session = GameSession(game: ShellCatch(random: Script([0, 0.5, 0.5, 0.5]).next), best: 3)
        var press = GameInput()
        press.pressed = true
        session.receive(press)
        for _ in 0..<(61 * 60) { session.advance(by: dt) }
        XCTAssertEqual(session.game.phase, .over)
        XCTAssertGreaterThan(session.best, 3)
        XCTAssertEqual(session.best, session.game.score)
        XCTAssertTrue(session.isNewBest)
    }
}

final class CatalogAndSheetTests: XCTestCase {
    private var repo: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func testCatalogIdsAreUniqueAndMakeFreshGames() {
        let ids = GameCatalog.all.map(\.id)
        XCTAssertFalse(ids.isEmpty)
        XCTAssertEqual(Set(ids).count, ids.count)
        for entry in GameCatalog.all {
            XCTAssertEqual(entry.make { $0.lowerBound }.phase, .ready)
        }
        XCTAssertNotNil(GameCatalog.entry(id: ShellCatch.id))
    }

    func testFramesWrapAround() {
        let item = GameSheet.Item(x: 10, y: 20, w: 16, h: 8, frames: 4)
        XCTAssertEqual(item.frame(0).x, 10)
        XCTAssertEqual(item.frame(2).x, 42)
        XCTAssertEqual(item.frame(5).x, 26)
        XCTAssertEqual(item.frame(-1).x, 58)
    }

    /// Every sprite a game draws exists in the bundled sheet and fits inside it.
    func testBundledSheetHasEverythingTheGamesDraw() throws {
        let sheet = try GameSheet(json: Data(contentsOf: repo.appendingPathComponent("Assets/Games/games.json")))
        let png = try Data(contentsOf: repo.appendingPathComponent("Assets/Games/games.png"))
        let width = png[16..<20].reduce(0) { $0 << 8 | Int($1) }
        let height = png[20..<24].reduce(0) { $0 << 8 | Int($1) }
        func fits(_ item: GameSheet.Item, _ label: String) {
            XCTAssertLessThanOrEqual(item.x + item.w * item.frames, width, label)
            XCTAssertLessThanOrEqual(item.y + item.h, height, label)
        }
        fits(sheet.chrome.frame, "chrome")
        fits(sheet.chrome.close, "close")
        XCTAssertEqual(sheet.chrome.frame.w - sheet.chrome.playfieldX * 2, Playfield.width)
        for entry in GameCatalog.all {
            let scene = entry.make { $0.lowerBound }.scene
            for name in [scene.background].compactMap({ $0 }) + scene.sprites.map(\.name) {
                guard let item = sheet.item(game: entry.id, name: name) else {
                    XCTFail("\(entry.id).\(name) missing from games.json")
                    continue
                }
                fits(item, "\(entry.id).\(name)")
            }
            let background = scene.background.flatMap { sheet.item(game: entry.id, name: $0) }
            XCTAssertEqual(background?.w, Playfield.width)
            XCTAssertEqual(background?.h, Playfield.height)
        }
    }
}
