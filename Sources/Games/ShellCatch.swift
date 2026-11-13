import Foundation

/// Shell Catch 🐚: Pibbo floats on his back along the bottom and moves left
/// and right (keys, a trackpad swipe or the mouse). Step 1 of the games work:
/// moving only; the falling shells come with step 2.
public struct ShellCatch: Game {
    public static let id = "shellCatch"

    /// Pibbo's sprite: as wide as a skin frame.
    static let pibboWidth = 16
    /// Top of Pibbo's sprite: his back rests on the water line of the background.
    static let pibboY = 96
    /// Speed with the keys held, art pixels per second.
    static let keySpeed: Double = 100
    /// Top speed while gliding toward the pointer.
    static let followSpeed: Double = 160

    public private(set) var score = 0
    public private(set) var phase: GamePhase = .ready
    /// Pibbo's left edge, in art pixels.
    public private(set) var pibboX: Double
    /// Where he glides to after the pointer moved (his centre), until a key or swipe takes over.
    private var target: Double?
    /// Time since the game opened, for the bobbing animation.
    private var clock: Double = 0

    private let random: (ClosedRange<Double>) -> Double

    public init(random: @escaping (ClosedRange<Double>) -> Double = { Double.random(in: $0) }) {
        self.random = random
        pibboX = Double(Playfield.width - Self.pibboWidth) / 2
    }

    static var maxX: Double { Double(Playfield.width - pibboWidth) }

    public mutating func step(_ input: GameInput, dt: Double) {
        clock += dt
        switch phase {
        case .ready, .over:
            if input.pressed {
                phase = .playing
                score = 0
            }
        case .playing:
            break
        }
        move(input, dt: dt)
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
        let bob = Int(clock * 3) % 4
        scene.sprites.append(GameSprite("pibbo", frame: bob, x: Int(pibboX.rounded()), y: Self.pibboY))
        let middle = Playfield.width / 2
        switch phase {
        case .ready:
            scene.texts.append(GameText(.clickToPlay, x: middle, y: 44, align: .center))
            scene.texts.append(GameText(.escToClose, x: middle, y: 58, align: .center))
        case .playing:
            scene.texts.append(GameText(.score(score), x: 4, y: 3))
        case .over:
            scene.texts.append(GameText(.score(score), x: middle, y: 40, align: .center))
            scene.texts.append(GameText(.clickToPlay, x: middle, y: 58, align: .center))
        }
        return scene
    }
}
