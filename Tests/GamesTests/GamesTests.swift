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
