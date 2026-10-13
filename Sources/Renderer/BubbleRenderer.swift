import AppKit
import Content

/// Draws Tidepool's pixel UI from the atlas in `Assets/UI` (ui.png + ui.json):
/// a 9-slice rounded frame, a tail pointing down at Pibbo, and pixel-font
/// text with pixel emoji icons. Used for speech bubbles and the click menu.
/// Images are 1 px per art pixel; windows scale them up with
/// nearest-neighbour filtering.
final class BubbleRenderer {
    private let font: PixelFont
    private let atlas: CGImage

    /// Extra space between menu lines, in art pixels.
    private let lineGap = 3

    enum TailPosition: Equatable {
        case right
        /// Tail centred on this x, in art pixels from the left edge.
        case at(Int)
    }
    private let tailRightMargin = 4
    private static let highlight = CGColor(red: 207 / 255, green: 234 / 255, blue: 247 / 255, alpha: 1)

    init(directory: URL) throws {
        font = try PixelFont(json: Data(contentsOf: directory.appendingPathComponent("ui.json")))
        guard let image = NSImage(contentsOf: directory.appendingPathComponent("ui.png"))?
            .cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw SkinError.unreadable(directory.appendingPathComponent("ui.png").path)
        }
        atlas = image
    }

    /// The tail's horizontal centre, in art pixels from the image's right edge,
    /// so a window can place the tail above Pibbo.
    var tailInsetFromRight: Int { tailRightMargin + (font.tail.w ?? 4) / 2 }

    /// A one-line speech bubble.
    func image(for text: String) -> CGImage? {
        image(lines: [text], highlighted: nil)
    }

    /// Vertical band of each line in art pixels from the image top, for hit
    /// testing menu items.
    func lineBands(count: Int) -> [ClosedRange<Int>] {
        (0..<count).map { index in
            let top = font.padding.top + index * (font.lineHeight + lineGap)
            return (top - lineGap / 2)...(top + font.lineHeight + lineGap / 2 - 1)
        }
    }

    /// A bubble with one or more lines; `highlighted` paints one line's band
    /// (the menu's hover state).
    func image(lines: [String], highlighted: Int?) -> CGImage? {
        let layouts = lines.map(font.layout)
        let padding = font.padding
        let textWidth = layouts.map(\.width).max() ?? 0
        let bodyWidth = textWidth + 2 * padding.x
        let textHeight = lines.count * font.lineHeight + max(0, lines.count - 1) * lineGap
        let bodyHeight = textHeight + padding.top + padding.bottom
        return drawBubble(bodyWidth: bodyWidth, bodyHeight: bodyHeight, tail: .right) { blit, context, height in
            // hover highlight, inside the border
            if let highlighted, lines.indices.contains(highlighted) {
                let band = self.lineBands(count: lines.count)[highlighted]
                context.setFillColor(Self.highlight)
                context.fill(CGRect(x: 2, y: height - band.upperBound - 1, width: bodyWidth - 4, height: band.count))
            }
            for (index, layout) in layouts.enumerated() {
                let top = padding.top + index * (self.font.lineHeight + self.lineGap)
                for glyph in layout.placed {
                    blit(glyph.glyph.x, glyph.glyph.y, glyph.glyph.w, self.font.lineHeight,
                         padding.x + glyph.x, top, glyph.glyph.w, self.font.lineHeight)
                }
            }
        }
    }

    /// The scrolling now-playing bubble: exactly `width` art pixels wide, with
    /// `icon` on the left, an empty text window, and the tail centred on
    /// `tailX`. Returns the frame and the text window (art pixels, top-left
    /// origin).
    func marqueeFrame(width: Int, tailX: Int, icon: String) -> (image: CGImage, window: CGRect)? {
        let padding = font.padding
        let iconLayout = font.layout(icon)
        let iconGap = 3
        let windowX = padding.x + iconLayout.width + iconGap
        let bodyWidth = width
        let textWidth = bodyWidth - windowX - padding.x
        guard textWidth > 8 else { return nil }
        let bodyHeight = font.lineHeight + padding.top + padding.bottom
        guard let image = drawBubble(bodyWidth: bodyWidth, bodyHeight: bodyHeight, tail: .at(tailX), content: { blit, _, _ in
            for glyph in iconLayout.placed {
                blit(glyph.glyph.x, glyph.glyph.y, glyph.glyph.w, self.font.lineHeight,
                     padding.x + glyph.x, padding.top, glyph.glyph.w, self.font.lineHeight)
            }
        }) else { return nil }
        return (image, CGRect(x: windowX, y: padding.top, width: textWidth, height: font.lineHeight))
    }

    /// One line of pixel text on a transparent background (1 px per art pixel).
    func textImage(_ text: String) -> CGImage? {
        let layout = font.layout(text)
        guard layout.width > 0,
              let context = CGContext(data: nil, width: layout.width, height: font.lineHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .none
        for glyph in layout.placed {
            guard let piece = atlas.cropping(to: CGRect(x: glyph.glyph.x, y: glyph.glyph.y, width: glyph.glyph.w, height: font.lineHeight)) else { continue }
            context.draw(piece, in: CGRect(x: glyph.x, y: 0, width: glyph.glyph.w, height: font.lineHeight))
        }
        return context.makeImage()
    }

    private typealias Blit = (_ sx: Int, _ sy: Int, _ sw: Int, _ sh: Int, _ dx: Int, _ dy: Int, _ dw: Int, _ dh: Int) -> Void

    /// Draws the 9-slice frame and tail, then lets `content` draw inside.
    private func drawBubble(bodyWidth: Int, bodyHeight: Int, tail: TailPosition,
                            content: (Blit, CGContext, Int) -> Void) -> CGImage? {
        let tailWidth = font.tail.w ?? 4, tailHeight = font.tail.h ?? 4
        let height = bodyHeight + tailHeight - 1  // the tail overlaps the bottom border
        guard let context = CGContext(data: nil, width: bodyWidth, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .none

        /// Copies an atlas rect (top-left origin) into the image (top-left origin), stretched.
        let copy: Blit = { sx, sy, sw, sh, dx, dy, dw, dh in
            guard dw > 0, dh > 0, let piece = self.atlas.cropping(to: CGRect(x: sx, y: sy, width: sw, height: sh)) else { return }
            context.draw(piece, in: CGRect(x: dx, y: height - dy - dh, width: dw, height: dh))
        }
        func blit(_ sx: Int, _ sy: Int, _ sw: Int, _ sh: Int, to dx: Int, _ dy: Int, _ dw: Int, _ dh: Int) {
            copy(sx, sy, sw, sh, dx, dy, dw, dh)
        }

        // 9-slice frame
        let b = font.bubble, size = b.size ?? 7, c = b.corner ?? 3
        let midW = bodyWidth - 2 * c, midH = bodyHeight - 2 * c
        blit(b.x, b.y, c, c, to: 0, 0, c, c)
        blit(b.x + size - c, b.y, c, c, to: bodyWidth - c, 0, c, c)
        blit(b.x, b.y + size - c, c, c, to: 0, bodyHeight - c, c, c)
        blit(b.x + size - c, b.y + size - c, c, c, to: bodyWidth - c, bodyHeight - c, c, c)
        blit(b.x + c, b.y, 1, c, to: c, 0, midW, c)
        blit(b.x + c, b.y + size - c, 1, c, to: c, bodyHeight - c, midW, c)
        blit(b.x, b.y + c, c, 1, to: 0, c, c, midH)
        blit(b.x + size - c, b.y + c, c, 1, to: bodyWidth - c, c, c, midH)
        blit(b.x + c, b.y + c, 1, 1, to: c, c, midW, midH)

        // tail
        let tailX: Int
        switch tail {
        case .right: tailX = bodyWidth - tailRightMargin - tailWidth
        case .at(let centre): tailX = min(max(centre - tailWidth / 2, 3), bodyWidth - 3 - tailWidth)
        }
        blit(font.tail.x, font.tail.y, tailWidth, tailHeight, to: tailX, bodyHeight - 1, tailWidth, tailHeight)

        content(copy, context, height)
        return context.makeImage()
    }
}
