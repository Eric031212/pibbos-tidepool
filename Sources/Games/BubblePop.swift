import Foundation

/// Bubble Pop 🫧 (v2.0): Pibbo floats in the water blowing bubbles; they rise
/// and wobble, and you click them before they float off the top. Some carry a
/// shell or a fish (worth more), small ones are worth a bit more, and now and
/// then a rainbow bubble pops everything around it. Missed bubbles just float
/// away. 60 s rounds that slowly get busier. Mouse or trackpad clicks only.
public struct BubblePop: Game {
    public static let id = "bubblePop"

    public enum Kind: String, CaseIterable, Sendable {
        case bubble, small, shell, fish, rainbow

        var points: Int {
            switch self {
            case .bubble, .rainbow: return 1
            case .small: return 2
            case .shell: return 3
            case .fish: return 5
            }
        }

        var weight: Double {
            switch self {
            case .bubble: return 6
            case .small: return 2.5
            case .shell: return 1.5
            case .fish: return 1
            case .rainbow: return 0.4
            }
        }

        /// How far from its centre a click still pops it.
        var hitRadius: Double { self == .small ? 5 : 7 }
        /// Small ones rise a bit faster.
        var speedFactor: Double { self == .small ? 1.25 : 1 }
    }

    public struct Bubble: Equatable, Sendable {
        public let kind: Kind
        /// Centre of the bubble's path and its height (art pixels).
        public let baseX: Double
        public var y: Double
        public let speed: Double
        public let phase: Double
        /// Where it is now: it wobbles side to side as it rises.
        public var x: Double { baseX + 3 * sin(y / 9 + phase) }
    }

    struct Effect: Equatable {
        let x: Int
        let y: Int
        var age: Double
    }

    static let size = 12
    /// Bubbles appear here (just under the water line) and leave above the top.
    static let startY = 98.0
    static let roundLength: Double = 60
    static let spawnInterval: (start: Double, end: Double) = (0.85, 0.35)
    static let riseSpeed: (start: Double, end: Double) = (18, 38)
    /// A rainbow bubble pops everything within this distance.
    static let rainbowReach: Double = 30
    static let restartDelay: Double = 1
    static let popLength: Double = 0.3
    static let pibboX = (Playfield.width - 16) / 2
    static let pibboY = 96

    public private(set) var score = 0
    public private(set) var phase: GamePhase = .ready
    public private(set) var bubbles: [Bubble] = []
    public private(set) var elapsed: Double = 0
    private var effects: [Effect] = []
    private var untilNext: Double = 0
    private var sinceOver: Double = 0
    private var clock: Double = 0
    private let random: (ClosedRange<Double>) -> Double

    public init(random: @escaping (ClosedRange<Double>) -> Double = { Double.random(in: $0) }) {
        self.random = random
    }

    public var secondsLeft: Int { Int((Self.roundLength - elapsed).rounded(.up)) }
    private var progress: Double { min(elapsed / Self.roundLength, 1) }

    public mutating func step(_ input: GameInput, dt: Double) {
        clock += dt
        effects = effects.compactMap { effect in
            var effect = effect
            effect.age += dt
            return effect.age < Self.popLength ? effect : nil
        }
        switch phase {
        case .ready:
            if input.pressed { startRound() }
        case .over:
            sinceOver += dt
            if input.pressed && sinceOver >= Self.restartDelay { startRound() }
        case .playing:
            if let tap = input.tap { pop(at: tap) }
            play(dt: dt)
        }
    }

    private mutating func startRound() {
        phase = .playing
        score = 0
        elapsed = 0
        bubbles = []
        untilNext = 0.3
    }

    private mutating func play(dt: Double) {
        elapsed += dt
        if elapsed >= Self.roundLength {
            phase = .over
            sinceOver = 0
            bubbles = []
            return
        }
        for index in bubbles.indices { bubbles[index].y -= bubbles[index].speed * dt }
        bubbles.removeAll { $0.y < -Double(Self.size) }  // floated away: no harm done
        untilNext -= dt
        if untilNext <= 0 {
            spawn()
            let interval = Self.spawnInterval.start + (Self.spawnInterval.end - Self.spawnInterval.start) * progress
            untilNext += interval * random(0.8...1.2)
        }
    }

    private mutating func spawn() {
        let kinds = Kind.allCases
        var roll = random(0...kinds.reduce(0) { $0 + $1.weight })
        var kind = kinds[kinds.count - 1]
        for candidate in kinds {
            if roll < candidate.weight { kind = candidate; break }
            roll -= candidate.weight
        }
        let margin = Double(Self.size) / 2 + 4
        let x = random(margin...(Double(Playfield.width) - margin))
        let speed = (Self.riseSpeed.start + (Self.riseSpeed.end - Self.riseSpeed.start) * progress) * kind.speedFactor * random(0.85...1.15)
        bubbles.append(Bubble(kind: kind, baseX: x, y: Self.startY, speed: speed, phase: random(0...(2 * Double.pi))))
    }

    /// A click: pops the nearest bubble under it (if any).
    private mutating func pop(at point: GamePoint) {
        func distance(_ b: Bubble) -> Double {
            let dx = b.x - point.x, dy = b.y - point.y
            return (dx * dx + dy * dy).squareRoot()
        }
        let hits = bubbles.indices.filter { distance(bubbles[$0]) <= bubbles[$0].kind.hitRadius }
        guard let index = hits.min(by: { distance(bubbles[$0]) < distance(bubbles[$1]) }) else { return }
        let hit = bubbles.remove(at: index)
        burst(hit)
        guard hit.kind == .rainbow else { return }
        let near = bubbles.filter { b in
            let dx = b.x - hit.x, dy = b.y - hit.y
            return (dx * dx + dy * dy).squareRoot() <= Self.rainbowReach
        }
        bubbles.removeAll { near.contains($0) }
        near.forEach { burst($0) }
    }

    private mutating func burst(_ bubble: Bubble) {
        score += bubble.kind.points
        let half = Double(Self.size) / 2
        effects.append(Effect(x: Int((bubble.x - half).rounded()), y: Int((bubble.y - half).rounded()), age: 0))
    }

    public var scene: GameScene {
        var scene = GameScene(background: "background")
        let half = Double(Self.size) / 2
        let tick = Int(clock * 4)
        scene.sprites.append(GameSprite("pibbo", frame: Int(clock * 3) % 4, x: Self.pibboX, y: Self.pibboY))
        for bubble in bubbles {
            scene.sprites.append(GameSprite(bubble.kind.rawValue, frame: tick % 2,
                                            x: Int((bubble.x - half).rounded()), y: Int((bubble.y - half).rounded())))
        }
        for effect in effects {
            let frame = min(Int(effect.age / Self.popLength * 3), 2)
            scene.sprites.append(GameSprite("pop", frame: frame, x: effect.x, y: effect.y))
        }
        let middle = Playfield.width / 2
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
