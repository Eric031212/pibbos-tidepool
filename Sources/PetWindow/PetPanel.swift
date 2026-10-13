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

    /// Bottom-right corner of the main display's visible frame: above a bottom
    /// Dock, beside a side Dock, at the edge when the Dock auto-hides.
    func moveToCorner() {
        guard let visible = NSScreen.screens.first?.visibleFrame else { return }
        setFrameOrigin(NSPoint(x: visible.maxX - frame.width, y: visible.minY))
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
    private let petRect: NSRect

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
        addTrackingArea(NSTrackingArea(rect: petRect, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHoverBegan?() }
    override func mouseExited(with event: NSEvent) { onHoverEnded?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if petRect.contains(convert(event.locationInWindow, from: nil)) { onClick?(event) }
    }
}
