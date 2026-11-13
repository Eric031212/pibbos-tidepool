import AppKit
import Games

/// The game's own window: an ordinary window that becomes key while it is in
/// front, so keys, swipes and clicks reach it without any global monitor or
/// permission (docs/games-plan.md). Borderless; the pixel frame is drawn.
final class GameWindow: NSWindow {
    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.moveToActiveSpace, .fullScreenNone]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Collects input over the game window and draws the frame and playfield
/// layers. All coordinates it reports are art pixels.
final class GameView: NSView {
    /// Art pixels → points.
    let scale: CGFloat
    private let chromeSize: CGSize
    private let playfield: CGRect  // art pixels, top-left origin
    private let closeRect: CGRect  // art pixels, top-left origin

    let chromeLayer = CALayer()
    let playLayer = CALayer()

    var onClose: (() -> Void)?
    var onCloseHover: ((Bool) -> Void)?
    /// A press while the game is paused only wakes it.
    var onPress: (() -> Void)?

    private var held = (left: false, right: false)
    private var pending = GameInput()
    private var closeHovered = false

    init(scale: Int, sheet: GameSheet) {
        self.scale = CGFloat(scale)
        let c = sheet.chrome
        chromeSize = CGSize(width: c.frame.w, height: c.frame.h)
        playfield = CGRect(x: c.playfieldX, y: c.playfieldY, width: Playfield.width, height: Playfield.height)
        closeRect = CGRect(x: c.closeX, y: c.closeY, width: c.close.w, height: c.close.h)
        super.init(frame: NSRect(x: 0, y: 0, width: chromeSize.width * self.scale, height: chromeSize.height * self.scale))
        wantsLayer = true
        layer = CALayer()
        for sublayer in [chromeLayer, playLayer] {
            sublayer.magnificationFilter = .nearest
            sublayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
            layer?.addSublayer(sublayer)
        }
        chromeLayer.frame = bounds
        playLayer.frame = CGRect(x: playfield.minX * self.scale,
                                 y: (chromeSize.height - playfield.maxY) * self.scale,
                                 width: playfield.width * self.scale, height: playfield.height * self.scale)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// What the player did since the last call: held keys plus the presses,
    /// swipes and pointer moves gathered in between.
    func takeInput() -> GameInput {
        var input = pending
        input.left = held.left
        input.right = held.right
        pending = GameInput()
        return input
    }

    /// Forget held keys (the window went to the back; their key-ups go elsewhere).
    func releaseKeys() {
        held = (false, false)
        pending = GameInput()
    }

    #if DEBUG
    func debug(_ command: String) {
        switch command {
        case "press": pending.pressed = true
        case "right": held.right = true
        case "stop": held = (false, false)
        default: break
        }
    }
    #endif

    // MARK: - Geometry

    /// A point in the view → art pixels, top-left origin.
    private func art(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x / scale, y: chromeSize.height - p.y / scale)
    }

    // MARK: - Mouse and trackpad

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let p = art(event)
        setCloseHovered(closeRect.contains(p))
        if playfield.insetBy(dx: 0, dy: -4).contains(p) {
            pending.pointerX = Double(p.x - playfield.minX)
        }
    }

    override func mouseDragged(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { setCloseHovered(false) }

    override func mouseDown(with event: NSEvent) {
        let p = art(event)
        if closeRect.contains(p) {
            onClose?()
        } else if playfield.contains(p) {
            press()
        } else {
            window?.performDrag(with: event)  // the frame moves the window
        }
    }

    override func scrollWheel(with event: NSEvent) {
        // Trackpad swipes only (precise deltas); a mouse wheel scrolls nothing here.
        guard event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return }
        // With natural scrolling the delta follows the fingers; without it, it's reversed.
        let fingers = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        pending.swipe += Double(fingers / scale)
    }

    private func setCloseHovered(_ hovered: Bool) {
        guard hovered != closeHovered else { return }
        closeHovered = hovered
        onCloseHover?(hovered)
    }

    private func press() {
        pending.pressed = true
        onPress?()
    }

    // MARK: - Keys

    private enum Key {
        static let left: UInt16 = 123, right: UInt16 = 124, a: UInt16 = 0, d: UInt16 = 2
        static let space: UInt16 = 49, returnKey: UInt16 = 36, enter: UInt16 = 76, escape: UInt16 = 53, w: UInt16 = 13
    }

    override func keyDown(with event: NSEvent) {
        // Never call super: unhandled keys would beep.
        switch event.keyCode {
        case Key.escape: onClose?()
        case Key.w where event.modifierFlags.contains(.command): onClose?()
        case Key.left, Key.a: held.left = true
        case Key.right, Key.d: held.right = true
        case Key.space, Key.returnKey, Key.enter: if !event.isARepeat { press() }
        default: break
        }
    }

    override func keyUp(with event: NSEvent) {
        switch event.keyCode {
        case Key.left, Key.a: held.left = false
        case Key.right, Key.d: held.right = false
        default: break
        }
    }
}
