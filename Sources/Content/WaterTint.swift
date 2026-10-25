import Foundation

/// Colours the tide pool for the time of day (CLAUDE.md Section 10): the skin
/// lists, per time of day, which water colours become which. Only the water
/// rows at the bottom of every frame are touched, so splashes, steam and
/// Pibbo himself keep their colours. Pure pixel arithmetic, done once per
/// change of the time of day.
public struct WaterTint: Equatable, Sendable {
    /// RGB (0xRRGGBB) → RGB.
    public let colors: [UInt32: UInt32]

    /// Rows at the bottom of each frame that are water (Section 11).
    public static let waterRows = 3

    /// `map`: "6fb7d9" → "c8b0da" (hex RGB, `#` optional). Nil if nothing parses.
    public init?(hex map: [String: String]) {
        var colors: [UInt32: UInt32] = [:]
        for (from, to) in map {
            guard let a = WaterTint.parse(from), let b = WaterTint.parse(to) else { continue }
            colors[a] = b
        }
        guard !colors.isEmpty else { return nil }
        self.colors = colors
    }

    public init(colors: [UInt32: UInt32]) {
        self.colors = colors
    }

    /// Mixes two RGB colours: `t` = 0 gives `a`, 1 gives `b`.
    public static func blend(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        let t = min(max(t, 0), 1)
        func channel(_ shift: UInt32) -> UInt32 {
            let x = Double(a >> shift & 0xFF), y = Double(b >> shift & 0xFF)
            return UInt32((x + (y - x) * t).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }

    static func parse(_ hex: String) -> UInt32? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6 else { return nil }
        return UInt32(digits, radix: 16)
    }

    /// Recolours opaque pixels in the water rows of every frame. `pixels` is
    /// RGBA, 8 bits per channel, rows top to bottom.
    public func recolor(_ pixels: UnsafeMutableBufferPointer<UInt8>, width: Int, height: Int, frameSize: Int) {
        guard frameSize > Self.waterRows, pixels.count >= width * height * 4 else { return }
        for y in 0..<height where y % frameSize >= frameSize - Self.waterRows {
            for x in 0..<width {
                let i = (y * width + x) * 4
                guard pixels[i + 3] == 255 else { continue }
                let rgb = UInt32(pixels[i]) << 16 | UInt32(pixels[i + 1]) << 8 | UInt32(pixels[i + 2])
                guard let new = colors[rgb] else { continue }
                pixels[i] = UInt8(new >> 16 & 0xFF)
                pixels[i + 1] = UInt8(new >> 8 & 0xFF)
                pixels[i + 2] = UInt8(new & 0xFF)
            }
        }
    }
}
