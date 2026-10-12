import AppKit
import Content
import QuartzCore

/// Plays skin clips as Core Animation keyframe animations on `contents`, so
/// the system render server animates Pibbo and this process stays idle
/// (spike 4: 0 % CPU, 0 wakeups). Discrete frames, nearest-neighbour scaling.
final class SpriteRenderer {
    let layer = CALayer()
    let pointSize: CGFloat

    private let pack: SkinPack
    private let sheet: CGImage
    private var frameCache: [String: [CGImage]] = [:]
    private(set) var currentClip: String?
    private var isPaused = false

    init(pack: SkinPack, scale: Int) throws {
        guard let image = NSImage(contentsOf: pack.spriteSheetURL)?
            .cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw SkinError.unreadable(pack.spriteSheetURL.path)
        }
        self.pack = pack
        sheet = image
        pointSize = CGFloat(pack.manifest.frameSize * scale)
        layer.frame = CGRect(x: 0, y: 0, width: pointSize, height: pointSize)
        layer.magnificationFilter = .nearest
        layer.actions = ["contents": NSNull(), "position": NSNull(), "bounds": NSNull()]
    }

    /// Shows a state or action by name, applying the pack's fallbacks.
    func show(_ name: String) {
        let (resolvedName, clip) = pack.resolve(name)
        guard resolvedName != currentClip else { return }
        currentClip = resolvedName

        let frames = self.frames(for: resolvedName, clip: clip)
        layer.removeAnimation(forKey: "frames")
        layer.contents = frames.first
        guard frames.count > 1 else { return }

        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = frames
        animation.calculationMode = .discrete
        // Discrete mode needs one more key time than values for equal slots.
        animation.keyTimes = (0...frames.count).map { NSNumber(value: Double($0) / Double(frames.count)) }
        animation.duration = Double(frames.count) / clip.fps
        animation.repeatCount = .infinity
        layer.add(animation, forKey: "frames")
    }

    func pause() {
        guard !isPaused else { return }
        isPaused = true
        layer.timeOffset = layer.convertTime(CACurrentMediaTime(), from: nil)
        layer.speed = 0
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        let pausedAt = layer.timeOffset
        layer.speed = 1
        layer.timeOffset = 0
        layer.beginTime = 0
        layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedAt
    }

    private func frames(for name: String, clip: Clip) -> [CGImage] {
        if let cached = frameCache[name] { return cached }
        let frames = pack.frameRects(for: clip).compactMap {
            sheet.cropping(to: CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height))
        }
        frameCache[name] = frames
        return frames
    }
}
