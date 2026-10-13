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
        let tailWidth = font.tail.w ?? 4, tailHeight = font.tail.h ?? 4
        let height = bodyHeight + tailHeight - 1  // the tail overlaps the bottom border
        guard let context = CGContext(data: nil, width: bodyWidth, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .none

        /// Copies an atlas rect (top-left origin) into the image (top-left origin), stretched.
        func blit(_ sx: Int, _ sy: Int, _ sw: Int, _ sh: Int, to dx: Int, _ dy: Int, _ dw: Int, _ dh: Int) {
            guard dw > 0, dh > 0, let piece = atlas.cropping(to: CGRect(x: sx, y: sy, width: sw, height: sh)) else { return }
            context.draw(piece, in: CGRect(x: dx, y: height - dy - dh, width: dw, height: dh))
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

        // tail, near the right edge
        blit(font.tail.x, font.tail.y, tailWidth, tailHeight,
             to: bodyWidth - tailRightMargin - tailWidth, bodyHeight - 1, tailWidth, tailHeight)

        // hover highlight, inside the border
        if let highlighted, lines.indices.contains(highlighted) {
            let band = lineBands(count: lines.count)[highlighted]
            context.setFillColor(Self.highlight)
            context.fill(CGRect(x: 2, y: height - band.upperBound - 1, width: bodyWidth - 4, height: band.count))
        }

        // text
        for (index, layout) in layouts.enumerated() {
            let top = padding.top + index * (font.lineHeight + lineGap)
            for glyph in layout.placed {
                blit(glyph.glyph.x, glyph.glyph.y, glyph.glyph.w, font.lineHeight,
                     to: padding.x + glyph.x, top, glyph.glyph.w, font.lineHeight)
            }
        }
        return context.makeImage()
    }
}
