import Foundation

/// Runs one open game: steps it at a fixed rate however the platform's frames
/// arrive, pauses it, and keeps its one best score (the only thing a game
/// remembers, docs/games-plan.md: no leaderboards, streaks or goals).
public struct GameSession {
    public static let stepLength: Double = 1.0 / 60
    /// At most this many steps per frame: after a hitch the game slows down
    /// for a moment instead of jumping ahead.
    static let maxStepsPerFrame = 5

    public private(set) var game: any Game
    public private(set) var isPaused = false
    /// The best score so far, including the current round once it is over.
    public private(set) var best: Int
    /// The round that just ended beat the old best.
    public private(set) var isNewBest = false

    private var input = GameInput()
    private var carry: Double = 0

    public init(game: any Game, best: Int) {
        self.game = game
        self.best = max(0, best)
    }

    /// The scene, with the session's own extras (paused, new best) left to the platform.
    public var scene: GameScene { game.scene }

    /// Merges what the player did since the last frame. Held keys replace the
    /// old ones; presses, swipes and pointer moves add up until a step sees them.
    public mutating func receive(_ new: GameInput) {
        input.left = new.left
        input.right = new.right
        if let x = new.pointerX { input.pointerX = x }
        input.swipe += new.swipe
        input.pressed = input.pressed || new.pressed
    }

    /// Steps the game for `seconds` of real time. Returns how many steps ran
    /// (0 while paused, or when less than a step has built up).
    @discardableResult
    public mutating func advance(by seconds: Double) -> Int {
        guard !isPaused, seconds > 0 else { return 0 }
        carry += seconds
        var steps = 0
        while carry >= Self.stepLength && steps < Self.maxStepsPerFrame {
            let before = game.phase
            if before != .playing && input.pressed { isNewBest = false }  // a new round starts
            game.step(input, dt: Self.stepLength)
            input.consumeEdges()
            carry -= Self.stepLength
            steps += 1
            if before == .playing && game.phase == .over && game.score > best {
                best = game.score
                isNewBest = true
            }
        }
        if steps == Self.maxStepsPerFrame { carry = 0 }
        return steps
    }

    /// The window went to the back: nothing moves until `resume()`.
    public mutating func pause() {
        isPaused = true
        input = GameInput()  // keys released while away would never arrive
        carry = 0
    }

    public mutating func resume() {
        isPaused = false
        carry = 0
    }
}
