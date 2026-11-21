import Foundation

/// The garden as a place to be in (v2.3): opened like a game in its own
/// window, but nothing is scored. Tap an empty plot to plant (a seed picker
/// opens), a growing plant to water it, a flower in bloom to pick it for the
/// pot by the pool. Pibbo walks to the plot and does it with you.
public struct GardenGame: Game {
    public static let id = "garden"

    /// Soil patches: left edge, top (art pixels). Two rows of three.
    static let plots: [(x: Int, y: Int)] = [(22, 64), (68, 64), (114, 64), (22, 92), (68, 92), (114, 92)]
    static let soilSize = (w: 24, h: 8)
    /// The seed picker panel and its icons.
    static let panel = (x: 38, y: 18, w: 84, h: 20)
    static let seedSize = 12
    static func seedOrigin(_ i: Int) -> (x: Int, y: Int) { (panel.x + 3 + i * 13, panel.y + 4) }
    static let walkSpeed: Double = 70
    static let messageLength: Double = 2
    static let actionLength: Double = 1.2

    public let score = 0
    public let phase: GamePhase = .playing

    private let store: GardenStore
    private let clock: GardenClock
    private let now: () -> Date
    /// "rain" or "snow" falls over the garden when it does outside.
    private let weather: String?
    public private(set) var state: GardenState
    /// The plot whose seed picker is open.
    public private(set) var picking: Int?
    private var pibbo = (x: 4.0, y: 82.0)
    private var target: (x: Double, y: Double)?
    private var action: (name: Int, until: Double)?  // frame of the action pose
    private var message: (key: GameText.Key, until: Double)?
    private var time: Double = 0

    public init(store: GardenStore, clock: GardenClock = GardenClock(), weather: String? = nil, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.clock = clock
        self.weather = weather
        self.now = now
        state = store.load()
    }

    public mutating func step(_ input: GameInput, dt: Double) {
        time += dt
        if let tap = input.tap { handle(tap) }
        if let (tx, ty) = target {
            let dx = tx - pibbo.x, dy = ty - pibbo.y
            let distance = (dx * dx + dy * dy).squareRoot()
            let reach = Self.walkSpeed * dt
            if distance <= reach { pibbo = (tx, ty); target = nil } else {
                pibbo = (pibbo.x + dx / distance * reach, pibbo.y + dy / distance * reach)
            }
        }
        if let a = action, a.until <= time { action = nil }
        if let m = message, m.until <= time { message = nil }
    }

    private mutating func handle(_ tap: GamePoint) {
        if let plot = picking {
            picking = nil
            for (i, kind) in FlowerKind.allCases.enumerated() {
                let o = Self.seedOrigin(i)
                if tap.x >= Double(o.x), tap.x < Double(o.x + Self.seedSize), tap.y >= Double(o.y), tap.y < Double(o.y + Self.seedSize) {
                    change(GardenRules.plant(kind, in: plot, of: state, now: now()))
                    goTo(plot, pose: 6, say: .planted)
                    return
                }
            }
            return  // a tap elsewhere just closes the picker
        }
        guard let index = Self.plotIndex(at: tap) else { return }
        guard let plot = state.plots[index] else {
            picking = index
            goTo(index, pose: nil, say: nil)
            return
        }
        if GardenRules.isInBloom(plot, now: now(), clock: clock) {
            change(GardenRules.pick(index, of: state, now: now(), clock: clock))
            goTo(index, pose: 6, say: .forThePool)
        } else {
            change(GardenRules.water(index, of: state, now: now(), clock: clock).state)
            goTo(index, pose: 4, say: .splash)
        }
    }

    /// Which plot a tap is on: the soil and the plant above it.
    static func plotIndex(at tap: GamePoint) -> Int? {
        plots.firstIndex { p in
            tap.x >= Double(p.x) && tap.x < Double(p.x + soilSize.w) && tap.y >= Double(p.y - 16) && tap.y < Double(p.y + soilSize.h)
        }
    }

    private mutating func change(_ new: GardenState) {
        guard new != state else { return }
        state = new
        store.save(new)
    }

    private mutating func goTo(_ index: Int, pose: Int?, say key: GameText.Key?) {
        let p = Self.plots[index]
        target = (Double(p.x - 14), Double(p.y - 12))
        if let pose { action = (pose, time + Self.actionLength) }
        if let key { message = (key, time + Self.messageLength) }
    }

    public var scene: GameScene {
        var scene = GameScene(background: "background")
        scene.showsBest = false
        let at = now()
        for (i, p) in Self.plots.enumerated() {
            let plot = state.plots[i]
            let wet = plot.map { GardenRules.wateredToday($0, now: at, clock: clock) } ?? false
            scene.sprites.append(GameSprite("soil", frame: wet ? 1 : 0, x: p.x, y: p.y))
            if let plot {
                scene.sprites.append(GameSprite(plot.kind.rawValue, frame: GardenRules.stage(plot, now: at, clock: clock),
                                                x: p.x + 4, y: p.y - 12))
            }
        }
        // Pibbo's frames: 0-1 idle, 2-3 walking, 4-5 watering, 6 holding a flower.
        let frame: Int
        if let pose = action?.name {
            frame = pose == 4 ? 4 + Int(time * 6) % 2 : pose
        } else if target != nil {
            frame = 2 + Int(time * 6) % 2
        } else {
            frame = Int(time * 2) % 2
        }
        scene.sprites.append(GameSprite("pibbo", frame: frame, x: Int(pibbo.x.rounded()), y: Int(pibbo.y.rounded())))
        if let weather, weather == "rain" || weather == "snow" {
            for i in 0..<18 {  // a light fall, worked out from the time: no state to keep
                let speed = weather == "rain" ? 90.0 : 18.0
                let x = (i * 37 + (weather == "snow" ? Int(sin(time + Double(i)) * 3) : 0)) % Playfield.width
                let y = Int(Double(i * 53) + time * speed) % Playfield.height
                scene.sprites.append(GameSprite(weather, x: (x + Playfield.width) % Playfield.width, y: y))
            }
        }
        if picking != nil {
            scene.sprites.append(GameSprite("panel", x: Self.panel.x, y: Self.panel.y))
            for i in FlowerKind.allCases.indices {
                let o = Self.seedOrigin(i)
                scene.sprites.append(GameSprite("seeds", frame: i, x: o.x, y: o.y))
            }
        }
        let middle = Playfield.width / 2
        let line: GameText.Key = message?.key ?? (picking != nil ? .pickSeed : .gardenHint)
        scene.texts.append(GameText(line, x: middle, y: picking != nil ? 42 : 3, align: .center))
        return scene
    }
}
