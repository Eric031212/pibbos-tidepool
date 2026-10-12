import AppKit

/// The transparent, always-on-top, non-activating window that holds Pibbo
/// (spike 3). It is exactly the size of the sprite; clicks on transparent
/// pixels pass through to the window behind.
final class PetPanel: NSPanel {
    let petView: PetView

    init(contentLayer: CALayer, size: CGFloat) {
        let frame = NSRect(x: 0, y: 0, width: size, height: size)
        petView = PetView(frame: frame, contentLayer: contentLayer)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        contentView = petView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Bottom-right corner of the main display's visible frame: above a bottom
    /// Dock, beside a side Dock, at the edge when the Dock auto-hides.
    func moveToCorner() {
        guard let visible = NSScreen.screens.first?.visibleFrame else { return }
        setFrameOrigin(NSPoint(x: visible.maxX - frame.width, y: visible.minY))
    }
}

final class PetView: NSView {
    var onHoverBegan: (() -> Void)?
    var onHoverEnded: (() -> Void)?
    var onClick: ((NSEvent) -> Void)?

    init(frame: NSRect, contentLayer: CALayer) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        layer?.addSublayer(contentLayer)
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
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHoverBegan?() }
    override func mouseExited(with event: NSEvent) { onHoverEnded?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?(event) }
}
