import AppKit

/// The now-playing bubble: a fixed-width pixel bubble centred above Pibbo
/// whose text ("theme - track") scrolls inside a fixed window.
///
/// The scroll is one Core Animation keyframe animation stepping exactly one
/// art pixel at a time (discrete), so the text stays crisp and the render
/// server does the work: no timers in our process.
final class MarqueePanel: NSPanel {
    private let renderer: BubbleRenderer
    private let scale: CGFloat
    private let frameLayer = CALayer()
    private let window = CALayer()
    private let strip = CALayer()
    private var currentText: String?

    /// Width of the text window, in art pixels; set by `show`.
    private var textWidth = 0
    /// Never narrower than this, in art pixels (skins without a flower).
    private let minimumWidth = 56
    /// Space between the end of the text and its next repeat.
    private let gap = 16
    /// Scroll speed in art pixels per second.
    private let speed: Double = 14
    private let icon = "♪"

    init(renderer: BubbleRenderer, scale: Int) {
        self.renderer = renderer
        self.scale = CGFloat(scale)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        configureAsOverlay(self)
        ignoresMouseEvents = true
        let view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer = CALayer()
        for layer in [frameLayer, strip] {
            layer.magnificationFilter = .nearest
            layer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        }
        window.masksToBounds = true
        window.actions = ["bounds": NSNull(), "position": NSNull()]
        view.layer?.addSublayer(frameLayer)
        view.layer?.addSublayer(window)
        window.addSublayer(strip)
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows `text` lined up with the tide pool below (`pool`, screen
    /// points): same left and right edges, tail over `tailX`, bottom at `bottomY`.
    func show(_ text: String, pool: NSRect, tailX: CGFloat, bottomY: CGFloat) {
        let width = max(Int(pool.width / scale), minimumWidth)
        var x = (pool.midX - CGFloat(width) * scale / 2).rounded()
        if let visible = NSScreen.screens.first?.visibleFrame {
            x = min(max(x, visible.minX), visible.maxX - CGFloat(width) * scale)
        }
        let tailArt = Int(((tailX - x) / scale).rounded())
        guard let (frameImage, textWindow) = renderer.marqueeFrame(width: width, tailX: tailArt, icon: icon) else { return }
        textWidth = Int(textWindow.width)
        let size = NSSize(width: CGFloat(frameImage.width) * scale, height: CGFloat(frameImage.height) * scale)
        setFrame(NSRect(x: x, y: bottomY, width: size.width, height: size.height), display: false)

        frameLayer.frame = CGRect(origin: .zero, size: size)
        frameLayer.contents = frameImage
        frameLayer.contentsScale = backingScaleFactor
        // Layer coordinates have their origin at the bottom left.
        window.frame = CGRect(x: textWindow.minX * scale,
                              y: (CGFloat(frameImage.height) - textWindow.maxY) * scale,
                              width: textWindow.width * scale, height: textWindow.height * scale)
        currentText = nil  // the window may have changed size: redo the text
        setText(text)
        orderFrontRegardless()
    }

    func hide() {
        strip.removeAllAnimations()
        currentText = nil
        orderOut(nil)
    }

    private func setText(_ text: String) {
        guard text != currentText, let line = renderer.textImage(text) else { return }
        currentText = text
        strip.removeAllAnimations()
        strip.contentsScale = backingScaleFactor
        let height = CGFloat(line.height) * scale

        guard line.width > textWidth else {
            // Fits: no scrolling, centred.
            strip.contents = line
            strip.frame = CGRect(x: ((CGFloat(textWidth - line.width) / 2).rounded()) * scale, y: 0,
                                 width: CGFloat(line.width) * scale, height: height)
            return
        }

        // Text, gap, text again: shifting left by one period loops seamlessly.
        let period = line.width + gap
        guard let context = CGContext(data: nil, width: period + line.width, height: line.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.draw(line, in: CGRect(x: 0, y: 0, width: line.width, height: line.height))
        context.draw(line, in: CGRect(x: period, y: 0, width: line.width, height: line.height))
        strip.contents = context.makeImage()
        strip.frame = CGRect(x: 0, y: 0, width: CGFloat(period + line.width) * scale, height: height)

        let start = strip.position.x
        let animation = CAKeyframeAnimation(keyPath: "position.x")
        // Discrete mode: one more key time than values; the last step wraps to 0.
        animation.values = (0..<period).map { start - CGFloat($0) * scale }
        animation.keyTimes = (0...period).map { NSNumber(value: Double($0) / Double(period)) }
        animation.calculationMode = .discrete
        animation.duration = Double(period) / speed
        animation.repeatCount = .infinity
        strip.add(animation, forKey: "scroll")
    }
}
