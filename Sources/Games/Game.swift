import Foundation

/// The little games you play with Pibbo (CLAUDE.md Section 3, docs/games-plan.md).
///
/// Pure rules, Foundation only, like Brain and World: no clock, no drawing, no
/// system input. The platform steps a game at a fixed rate with what the
/// player did (`GameInput`) and draws what it describes (`GameScene`).

/// Size of every game's playfield, in art pixels (drawn at an integer scale).
public enum Playfield {
    public static let width = 160
    public static let height = 120
}

/// What the player did, gathered by the platform from its own game window only.
public struct GameInput: Equatable, Sendable {
    /// Arrow keys (or A / D) held down right now.
    public var left = false
    public var right = false
    /// Where the pointer is over the playfield (art pixels from the left),
    /// set only when it moved since the last step.
    public var pointerX: Double?
    /// Horizontal trackpad swipe since the last step, in art pixels
    /// (positive = fingers moved right).
    public var swipe: Double = 0
    /// A click on the playfield, space or return since the last step.
    public var pressed = false

    public init() {}

    /// Clears what happens once (a press, a swipe, a pointer move) and keeps
    /// what is held (keys), after a step has seen it.
    mutating func consumeEdges() {
        pointerX = nil
        swipe = 0
        pressed = false
    }
}

public enum GamePhase: Equatable, Sendable {
    /// Waiting for a click to start.
    case ready
    case playing
    /// The round is over; a click starts another.
    case over
}

/// A sprite to draw: `name` is a key of the game's sheet, `frame` an index
/// into its frames, `x`/`y` its top-left corner in art pixels (top-left origin).
public struct GameSprite: Equatable, Sendable {
    public var name: String
    public var frame: Int
    public var x: Int
    public var y: Int

    public init(_ name: String, frame: Int = 0, x: Int, y: Int) {
        self.name = name
        self.frame = frame
        self.x = x
        self.y = y
    }
}

/// A line of pixel text. Games name strings by key (`GameText.Key`), so the
/// rules never hold user-visible text (CLAUDE.md Section 6).
public struct GameText: Equatable, Sendable {
    public enum Key: Equatable, Sendable {
        case clickToPlay, escToClose, newBest
        case score(Int)
        case best(Int)
    }

    public enum Align: Equatable, Sendable { case left, center, right }

    public var key: Key
    /// Anchor in art pixels: the left edge, centre or right edge (by `align`)
    /// and the top of the line.
    public var x: Int
    public var y: Int
    public var align: Align

    public init(_ key: Key, x: Int, y: Int, align: Align = .left) {
        self.key = key
        self.x = x
        self.y = y
        self.align = align
    }
}

/// Everything on the playfield for one frame, back to front.
public struct GameScene: Equatable, Sendable {
    /// The game's static background (a sheet key), drawn first.
    public var background: String?
    public var sprites: [GameSprite] = []
    public var texts: [GameText] = []

    public init(background: String? = nil) {
        self.background = background
    }
}

/// One game's rules.
public protocol Game {
    /// The current round's score.
    var score: Int { get }
    var phase: GamePhase { get }
    /// What to draw now.
    var scene: GameScene { get }
    /// Advances the rules by `dt` seconds (the platform's fixed step).
    mutating func step(_ input: GameInput, dt: Double)
}
