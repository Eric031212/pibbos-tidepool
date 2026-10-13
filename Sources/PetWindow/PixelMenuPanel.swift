import AppKit

/// Pibbo's click menu, drawn in the same pixel style as his speech bubbles
/// instead of a system menu. Hover highlights a line; a click picks it.
///
/// Closes when an item is picked, when the mouse has been away for a moment,
/// or when the owner calls `close()` (another click on Pibbo, another app
/// activated). No global event monitors, so no permission questions.
final class PixelMenuPanel: NSPanel {
    struct Item {
        let title: String
        let action: () -> Void
    }

    private let renderer: BubbleRenderer
    private let scale: CGFloat
    private let imageLayer = CALayer()
    private var items: [Item] = []
    private var highlighted: Int?
    private var closeTimer: Timer?

    /// How long the mouse may wander off before the menu closes.
    private let graceAfterExit: TimeInterval = 1.2
    /// Closes by itself if the mouse never comes over at all.
    private let graceAfterOpen: TimeInterval = 4

    var isOpen: Bool { isVisible }

    init(renderer: BubbleRenderer, scale: Int) {
        self.renderer = renderer
        self.scale = CGFloat(scale)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        configureAsOverlay(self)
        let view = MenuView(frame: .zero)
        view.wantsLayer = true
        view.layer = CALayer()
        imageLayer.magnificationFilter = .nearest
        imageLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        view.layer?.addSublayer(imageLayer)
        view.onMove = { [weak self] point in self?.hover(at: point) }
        view.onExit = { [weak self] in self?.mouseLeft() }
        view.onEnter = { [weak self] in self?.closeTimer?.invalidate() }
        view.onClick = { [weak self] point in self?.click(at: point) }
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Opens above Pibbo with the tail over `anchorX`, bottom at `bottomY`.
    func open(_ items: [Item], anchorX: CGFloat, bottomY: CGFloat) {
        self.items = items
        highlighted = nil
        guard let image = render() else { return }
        let size = NSSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        var x = anchorX - size.width + CGFloat(renderer.tailInsetFromRight) * scale
        if let visible = NSScreen.screens.first?.visibleFrame {
            x = min(max(x, visible.minX), visible.maxX - size.width)
        }
        setFrame(NSRect(x: x, y: bottomY, width: size.width, height: size.height), display: false)
        imageLayer.frame = CGRect(origin: .zero, size: size)
        imageLayer.contentsScale = backingScaleFactor
        imageLayer.contents = image
        contentView?.updateTrackingAreas()
        orderFrontRegardless()
        scheduleClose(after: graceAfterOpen)
    }

    override func close() {
        closeTimer?.invalidate()
        closeTimer = nil
        orderOut(nil)
    }

    private func render() -> CGImage? {
        renderer.image(lines: items.map(\.title), highlighted: highlighted)
    }

    /// Which item is under a point in view coordinates.
    private func item(at point: NSPoint) -> Int? {
        guard let height = contentView?.bounds.height else { return nil }
        let artY = Int((height - point.y) / scale)
        return renderer.lineBands(count: items.count).firstIndex { $0.contains(artY) }
    }

    private func hover(at point: NSPoint) {
        let index = item(at: point)
        guard index != highlighted else { return }
        highlighted = index
        imageLayer.contents = render()
    }

    private func mouseLeft() {
        if highlighted != nil {
            highlighted = nil
            imageLayer.contents = render()
        }
        scheduleClose(after: graceAfterExit)
    }

    private func scheduleClose(after delay: TimeInterval) {
        closeTimer?.invalidate()
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in self?.close() }
        RunLoop.main.add(timer, forMode: .common)
        closeTimer = timer
    }

    private func click(at point: NSPoint) {
        guard let index = item(at: point) else { return }
        let action = items[index].action
        close()
        action()
    }
}

private final class MenuView: NSView {
    var onMove: ((NSPoint) -> Void)?
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    var onClick: ((NSPoint) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
    override func mouseMoved(with event: NSEvent) { onMove?(convert(event.locationInWindow, from: nil)) }
    override func mouseDown(with event: NSEvent) { onClick?(convert(event.locationInWindow, from: nil)) }
}
