import AppKit

/// The transparent, always-on-top, non-activating window that holds Pibbo
/// (spike 3) and, to his left, his flower. It is exactly the size of the
/// sprites; clicks on transparent pixels pass through to the window behind.
final class PetPanel: NSPanel {
    let petView: PetView

    /// `petRect`: where Pibbo sits; only that area reacts to hover and clicks.
    init(layers: [CALayer], size: NSSize, petRect: NSRect) {
        let frame = NSRect(origin: .zero, size: size)
        petView = PetView(frame: frame, layers: layers, petRect: petRect)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        configureAsOverlay(self)
        contentView = petView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Where along the bottom edge the pool sits: 0 = far left, 1 = far right
    /// (the default corner). Kept as a fraction so it survives resolution and
    /// Dock changes.
    private(set) var shorePosition: CGFloat = {
        let saved = UserDefaults.standard.object(forKey: PetPanel.shoreKey) as? Double
        return CGFloat(saved ?? 1)
    }()
    private static let shoreKey = "shorePosition"

    /// Sits on the bottom edge of the main display's visible frame (above a
    /// bottom Dock, beside a side Dock, at the edge when it auto-hides), at
    /// `shorePosition` along it.
    func moveToShore() {
        guard let visible = NSScreen.screens.first?.visibleFrame else { return }
        let travel = max(0, visible.width - frame.width)
        setFrameOrigin(NSPoint(x: (visible.minX + travel * shorePosition).rounded(), y: visible.minY))
    }

    /// Follows a drag horizontally; the pool always stays on the shore.
    func slide(toX x: CGFloat) {
        guard let visible = NSScreen.screens.first?.visibleFrame else { return }
        let travel = max(1, visible.width - frame.width)
        shorePosition = min(max((x - visible.minX) / travel, 0), 1)
        moveToShore()
    }

    func rememberShorePosition() {
        UserDefaults.standard.set(Double(shorePosition), forKey: Self.shoreKey)
    }
}

/// Shared window setup for Tidepool's overlays (spike 3).
func configureAsOverlay(_ panel: NSPanel) {
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .floating
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = true
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
}

final class PetView: NSView {
    var onHoverBegan: (() -> Void)?
    var onHoverEnded: (() -> Void)?
    var onClick: ((NSEvent) -> Void)?
    /// New left edge of the window while Pibbo is dragged (screen points).
    var onDrag: ((CGFloat) -> Void)?
    var onDragEnded: (() -> Void)?
    /// The mouse rubbed back and forth over Pibbo.
    var onRub: (() -> Void)?
    /// The mouse rested still on Pibbo / moved off again.
    var onHoldBegan: (() -> Void)?
    var onHoldEnded: (() -> Void)?
    /// A click on the water/flower beside Pibbo, at this x (view points).
    var onSplash: ((CGFloat) -> Void)?
    private let petRect: NSRect

    // Rub: this many direction changes, each after at least `rubStroke` of
    // travel, within `rubWindow` seconds.
    private let rubReversals = 4
    private let rubStroke: CGFloat = 4
    private let rubWindow: TimeInterval = 1.5
    private var lastMoveX: CGFloat?
    private var moveDirection: CGFloat = 0
    private var strokeTravel: CGFloat = 0
    private var reversalTimes: [TimeInterval] = []

    // Hold: the cursor stays within `holdSlop` for `holdDelay` seconds.
    private let holdDelay: TimeInterval = 2
    private let holdSlop: CGFloat = 3
    private var holdAnchor: NSPoint = .zero
    private var holdTimer: DispatchWorkItem?
    private var isHolding = false

    /// A press only becomes a drag after moving this far (points); otherwise
    /// it is a click.
    private let dragThreshold: CGFloat = 4
    private var pressStart: NSPoint?
    private var windowStartX: CGFloat = 0
    private var isDragging = false

    init(frame: NSRect, layers: [CALayer], petRect: NSRect) {
        self.petRect = petRect
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        layers.forEach { layer?.addSublayer($0) }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        layer?.sublayers?.forEach { $0.contentsScale = scale }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // `.activeAlways`: hover works while another app is frontmost.
        // Tracking is geometric (spike 3), so it covers Pibbo only, not the flower.
        // Mouse moves are only delivered while the cursor is over Pibbo.
        addTrackingArea(NSTrackingArea(rect: petRect, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverBegan?()
        restartHoldTimer(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        cancelHold()
        resetRub()
        onHoverEnded?()
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard petRect.contains(point) else { return }
        trackRub(x: point.x)
        if hypot(point.x - holdAnchor.x, point.y - holdAnchor.y) > holdSlop {
            cancelHold()
            restartHoldTimer(at: point)
        }
    }

    private func trackRub(x: CGFloat) {
        defer { lastMoveX = x }
        guard let last = lastMoveX else { return }
        let dx = x - last
        guard abs(dx) >= 0.5 else { return }
        let direction: CGFloat = dx > 0 ? 1 : -1
        if direction != moveDirection && strokeTravel >= rubStroke {
            let now = ProcessInfo.processInfo.systemUptime
            reversalTimes = reversalTimes.filter { now - $0 < rubWindow } + [now]
            strokeTravel = 0
            if reversalTimes.count >= rubReversals {
                resetRub()
                cancelHold()
                onRub?()
                return
            }
        } else if direction != moveDirection {
            strokeTravel = 0
        }
        moveDirection = direction
        strokeTravel += abs(dx)
    }

    private func resetRub() {
        lastMoveX = nil
        moveDirection = 0
        strokeTravel = 0
        reversalTimes = []
    }

    private func restartHoldTimer(at point: NSPoint) {
        holdAnchor = point
        holdTimer?.cancel()
        let timer = DispatchWorkItem { [weak self] in
            guard let self, !self.isHolding else { return }
            self.isHolding = true
            self.onHoldBegan?()
        }
        holdTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + holdDelay, execute: timer)
    }

    private func cancelHold() {
        holdTimer?.cancel()
        holdTimer = nil
        if isHolding {
            isHolding = false
            onHoldEnded?()
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        cancelHold()
        if point.x < petRect.minX {
            onSplash?(point.x)  // the water and flower beside him
            return
        }
        guard petRect.contains(point) else { return }
        pressStart = NSEvent.mouseLocation
        windowStartX = window?.frame.minX ?? 0
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = pressStart else { return }
        let dx = NSEvent.mouseLocation.x - start.x
        if !isDragging && abs(dx) < dragThreshold { return }
        isDragging = true
        onDrag?(windowStartX + dx)
    }

    override func mouseUp(with event: NSEvent) {
        guard pressStart != nil else { return }
        pressStart = nil
        if isDragging {
            isDragging = false
            onDragEnded?()
        } else {
            onClick?(event)
        }
    }
}
