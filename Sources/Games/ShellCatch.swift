import Foundation

/// Shell Catch 🐚: Pibbo floats on his back along the bottom and moves left
/// and right (keys, a trackpad swipe or the mouse) to catch what falls:
/// shells (1), starfish (2) and little fish (3). A jellyfish makes him dizzy
/// for a moment (he can't move) but never costs points. A round lasts 60 s
/// and slowly gets faster. Missing things costs nothing: calm on purpose.
public struct ShellCatch: Game {
    public static let id = "shellCatch"

    public enum Kind: String, CaseIterable, Sendable {
        case shell, starfish, fish, jelly

        var points: Int {
            switch self {
            case .shell: return 1
            case .starfish: return 2
            case .fish: return 3
            case .jelly: return 0
            }
        }

        /// How often each one falls, relative to the others.
        var weight: Double {
            switch self {
            case .shell: return 6
            case .starfish: return 3
            case .fish: return 1.2
            case .jelly: return 1.8
            }
        }

        /// Jellyfish drift down more slowly.
        var speedFactor: Double { self == .jelly ? 0.7 : 1 }
    }

    public struct Item: Equatable, Sendable {
        public let kind: Kind
        /// Left edge and top, in art pixels.
        public var x: Double
        public var y: Double
        public let speed: Double
    }

    /// A short effect: a sparkle where something was caught, a splash where it fell in.
    struct Effect: Equatable {
        let name: String
        let x: Int
        let y: Int
        var age: Double
        let length: Double
    }

    // Layout (art pixels).
    static let pibboWidth = 16
    /// Top of Pibbo's sprite: his back rests on the water line of the background.
    static let pibboY = 96
    /// Items are 12×12.
    static let itemSize = 12
    /// What falls is caught when its bottom reaches his belly...
    static let catchLine = 98
    /// ...and lost once it reaches the water.
    static let waterLine = 104

    // Tuning.
    static let roundLength: Double = 60
    static let keySpeed: Double = 100
    static let followSpeed: Double = 160
    static let dizzyLength: Double = 1.5
    /// Seconds between items at the start and at the end of a round.
    static let spawnInterval: (start: Double, end: Double) = (1.1, 0.45)
    /// Fall speed (art pixels per second) at the start and at the end.
    static let fallSpeed: (start: Double, end: Double) = (30, 62)
    /// After a round ends, clicks are ignored this long (no accidental restart).
    static let restartDelay: Double = 1

    public private(set) var score = 0
    public private(set) var phase: GamePhase = .ready
    /// Pibbo's left edge.
    public private(set) var pibboX: Double
    public private(set) var items: [Item] = []
    /// Seconds played in this round.
    public private(set) var elapsed: Double = 0
    /// While > 0 he's dizzy from a jellyfish and can't move.
    public private(set) var dizzy: Double = 0
    private var effects: [Effect] = []
    private var target: Double?
    private var untilNextItem: Double = 0
    private var sinceOver: Double = 0
    private var clock: Double = 0

    private let random: (ClosedRange<Double>) -> Double

    public init(random: @escaping (ClosedRange<Double>) -> Double = { Double.random(in: $0) }) {
        self.random = random
        pibboX = Double(Playfield.width - Self.pibboWidth) / 2
    }

    static var maxX: Double { Double(Playfield.width - pibboWidth) }

    /// Seconds left in the round, rounded up (60 … 0).
    public var secondsLeft: Int { Int((Self.roundLength - elapsed).rounded(.up)) }

    /// 0 at the start of a round, 1 at the end.
    private var progress: Double { min(elapsed / Self.roundLength, 1) }

    public mutating func step(_ input: GameInput, dt: Double) {
        clock += dt
        effects = effects.compactMap { effect in
            var effect = effect
            effect.age += dt
            return effect.age < effect.length ? effect : nil
        }
        switch phase {
        case .ready:
            if input.pressed { startRound() }
        case .over:
            sinceOver += dt
            if input.pressed && sinceOver >= Self.restartDelay { startRound() }
        case .playing:
            play(dt: dt)
        }
        dizzy = max(0, dizzy - dt)
        if dizzy == 0 { move(input, dt: dt) } else { target = nil }
        if phase == .playing { catchAndMiss() }
    }

    private mutating func startRound() {
        phase = .playing
        score = 0
        elapsed = 0
        dizzy = 0
        items = []
        untilNextItem = 0.6
    }

    private mutating func play(dt: Double) {
        elapsed += dt
        if elapsed >= Self.roundLength {
            phase = .over
            sinceOver = 0
            items = []
            dizzy = 0
            return
        }
        for index in items.indices { items[index].y += items[index].speed * dt }
        untilNextItem -= dt
        if untilNextItem <= 0 {
            spawn()
            let interval = Self.spawnInterval.start + (Self.spawnInterval.end - Self.spawnInterval.start) * progress
            untilNextItem += interval * random(0.8...1.2)
        }
    }

    private mutating func spawn() {
        let kinds = Kind.allCases
        let total = kinds.reduce(0) { $0 + $1.weight }
        var roll = random(0...total)
        var kind = kinds[0]
        for candidate in kinds {
            if roll < candidate.weight { kind = candidate; break }
            roll -= candidate.weight
            kind = candidate
        }
        let x = random(2...Double(Playfield.width - Self.itemSize - 2))
        let base = Self.fallSpeed.start + (Self.fallSpeed.end - Self.fallSpeed.start) * progress
        items.append(Item(kind: kind, x: x, y: -Double(Self.itemSize), speed: base * kind.speedFactor * random(0.85...1.15)))
    }

    private mutating func catchAndMiss() {
        let left = pibboX - 2, right = pibboX + Double(Self.pibboWidth) + 2
        var kept: [Item] = []
        for item in items {
            let bottom = item.y + Double(Self.itemSize)
            let centre = item.x + Double(Self.itemSize) / 2
            if bottom >= Double(Self.catchLine) && bottom < Double(Self.waterLine) && centre >= left && centre <= right {
                if item.kind == .jelly {
                    dizzy = Self.dizzyLength
                } else {
                    score += item.kind.points
                    effects.append(Effect(name: "sparkle", x: Int(item.x), y: Self.catchLine - Self.itemSize - 2, age: 0, length: 0.4))
                }
            } else if bottom >= Double(Self.waterLine) {
                effects.append(Effect(name: "splash", x: Int(item.x), y: Self.waterLine - Self.itemSize + 4, age: 0, length: 0.45))
            } else {
                kept.append(item)
            }
        }
        items = kept
    }

    /// He swims in every phase, so the player can try the controls before starting.
    private mutating func move(_ input: GameInput, dt: Double) {
        if let pointer = input.pointerX { target = pointer }
        let direction = (input.right ? 1.0 : 0) - (input.left ? 1.0 : 0)
        if direction != 0 || input.swipe != 0 { target = nil }
        var x = pibboX + direction * Self.keySpeed * dt + input.swipe
        if let target {
            let wanted = target - Double(Self.pibboWidth) / 2 - x
            let reach = Self.followSpeed * dt
            x += min(max(wanted, -reach), reach)
        }
        pibboX = min(max(x, 0), Self.maxX)
    }

    public var scene: GameScene {
        var scene = GameScene(background: "background")
        let middle = Playfield.width / 2
        let tick = Int(clock * 4)
        for item in items {
            scene.sprites.append(GameSprite(item.kind.rawValue, frame: tick % 2, x: Int(item.x.rounded()), y: Int(item.y.rounded())))
        }
        for effect in effects {
            let frames = effect.name == "splash" ? 3 : 2
            let frame = min(Int(effect.age / effect.length * Double(frames)), frames - 1)
            scene.sprites.append(GameSprite(effect.name, frame: frame, x: effect.x, y: effect.y))
        }
        let x = Int(pibboX.rounded())
        scene.sprites.append(GameSprite("pibbo", frame: Int(clock * 3) % 4, x: x, y: Self.pibboY))
        if dizzy > 0 {
            scene.sprites.append(GameSprite("dizzy", frame: tick % 4, x: x + 4, y: Self.pibboY - 9))
        }
        switch phase {
        case .ready:
            scene.texts.append(GameText(.clickToPlay, x: middle, y: 44, align: .center))
            scene.texts.append(GameText(.escToClose, x: middle, y: 58, align: .center))
        case .playing:
            scene.texts.append(GameText(.score(score), x: 4, y: 3))
            scene.texts.append(GameText(.timeLeft(secondsLeft), x: middle, y: 3, align: .center))
        case .over:
            scene.texts.append(GameText(.timeUp, x: middle, y: 38, align: .center))
            scene.texts.append(GameText(.score(score), x: middle, y: 52, align: .center))
            if sinceOver >= Self.restartDelay {
                scene.texts.append(GameText(.clickToPlay, x: middle, y: 70, align: .center))
            }
        }
        return scene
    }
}
