import AppKit
import Content
import QuartzCore

/// Plays skin clips as Core Animation keyframe animations on `contents`, so
/// the system render server animates Pibbo and this process stays idle
/// (spike 4: 0 % CPU, 0 wakeups). Discrete frames, nearest-neighbour scaling.
/// Also shows the skin's optional flower in `gardenLayer`.
final class SpriteRenderer {
    let layer = CALayer()
    let gardenLayer = CALayer()
    /// Splash effect drawn over the water where the user clicked.
    let rippleLayer = CALayer()
    let pointSize: CGFloat
    var hasGarden: Bool { pack.manifest.garden != nil }

    private let pack: SkinPack
    private let sheet: CGImage
    private var frameCache: [String: [CGImage]] = [:]
    private(set) var currentClip: String?
    private var isPaused = false

    /// Holiday outfit worn by every clip (nil = none). Setting it redraws
    /// the current clip on the next `show`.
    var outfit: String? {
        didSet { if outfit != oldValue { currentClip = nil } }
    }

    init(pack: SkinPack, scale: Int) throws {
        guard let image = NSImage(contentsOf: pack.spriteSheetURL)?
            .cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw SkinError.unreadable(pack.spriteSheetURL.path)
        }
        self.pack = pack
        sheet = image
        pointSize = CGFloat(pack.manifest.frameSize * scale)
        let noFades: [String: CAAction] = ["contents": NSNull(), "position": NSNull(), "bounds": NSNull(), "hidden": NSNull()]
        rippleLayer.isHidden = true
        for sprite in [layer, gardenLayer, rippleLayer] {
            sprite.frame = CGRect(x: 0, y: 0, width: pointSize, height: pointSize)
            sprite.magnificationFilter = .nearest
            sprite.actions = noFades
        }
    }

    private var gardenStage: Int?

    /// Shows the flower at a growth stage (no-op for skins without a garden).
    func showGarden(stage: Int) {
        guard stage != gardenStage, let rect = pack.gardenFrameRect(stage: stage) else { return }
        gardenStage = stage
        gardenLayer.contents = sheet.cropping(to: CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height))
    }

    /// Shows a state or action by name, applying the pack's fallbacks.
    func show(_ name: String) {
        let (resolvedName, clip) = pack.resolve(name, outfit: outfit)
        guard resolvedName != currentClip else { return }
        currentClip = resolvedName

        let frames = self.frames(for: "\(resolvedName)#\(outfit ?? "")", clip: clip)
        layer.removeAnimation(forKey: "frames")
        layer.contents = frames.first
        guard frames.count > 1 else { return }

        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = frames
        animation.calculationMode = .discrete
        // Discrete mode needs one more key time than values for equal slots.
        animation.keyTimes = (0...frames.count).map { NSNumber(value: Double($0) / Double(frames.count)) }
        animation.duration = Double(frames.count) / clip.fps
        if clip.loops {
            animation.repeatCount = .infinity
        } else {
            // Play once and hold the last frame (e.g. `unplug`).
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            layer.contents = frames.last
        }
        layer.add(animation, forKey: "frames")
    }

    /// Plays the skin's `ripple` effect once, centred on `x` (layer points),
    /// kept inside `width`. No-op for skins without one.
    func playRipple(atX x: CGFloat, within width: CGFloat) {
        guard let clip = pack.manifest.actions?["ripple"] else { return }
        let frames = self.frames(for: "ripple", clip: clip)
        guard !frames.isEmpty else { return }
        rippleLayer.removeAllAnimations()
        rippleLayer.frame.origin.x = min(max((x - pointSize / 2).rounded(), 0), width - pointSize)
        rippleLayer.contents = frames.last
        rippleLayer.isHidden = false

        let duration = Double(frames.count) / clip.fps
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = frames
        animation.calculationMode = .discrete
        animation.keyTimes = (0...frames.count).map { NSNumber(value: Double($0) / Double(frames.count)) }
        animation.duration = duration
        rippleLayer.add(animation, forKey: "ripple")
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.rippleLayer.isHidden = true
        }
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
