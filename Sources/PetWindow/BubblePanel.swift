import AppKit

/// A pixel speech bubble floating above Pibbo. Clickable, never activates
/// the app or takes focus.
final class BubblePanel: NSPanel {
    var onClick: (() -> Void)?
    private let imageLayer = CALayer()
    private let scale: CGFloat

    init(scale: Int) {
        self.scale = CGFloat(scale)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        configureAsOverlay(self)
        let view = BubbleView(frame: .zero)
        view.wantsLayer = true
        view.layer = CALayer()
        imageLayer.magnificationFilter = .nearest
        imageLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        view.layer?.addSublayer(imageLayer)
        view.onClick = { [weak self] in self?.onClick?() }
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows `image` with its tail (`tailInsetFromRight` art pixels from the
    /// right edge) over `anchorX`, its bottom at `bottomY` (screen points).
    func show(_ image: CGImage, tailInsetFromRight: Int, anchorX: CGFloat, bottomY: CGFloat) {
        let size = NSSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        var x = anchorX - size.width + CGFloat(tailInsetFromRight) * scale
        if let visible = NSScreen.screens.first?.visibleFrame {
            x = min(max(x, visible.minX), visible.maxX - size.width)
        }
        setFrame(NSRect(x: x, y: bottomY, width: size.width, height: size.height), display: false)
        imageLayer.frame = CGRect(origin: .zero, size: size)
        imageLayer.contents = image
        imageLayer.contentsScale = backingScaleFactor
        orderFrontRegardless()
    }
}

private final class BubbleView: NSView {
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
}
