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
    /// Length of the in-between played by the last clip switch (0 = a cut).
    private var transitionDuration: CFTimeInterval = 0
    private var gardenVisible = true
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
        let noFades: [String: CAAction] = ["contents": NSNull(), "position": NSNull(), "bounds": NSNull(), "hidden": NSNull(), "opacity": NSNull()]
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

    /// Shows or hides the flower in step with Pibbo's last clip switch: it
    /// stays until he has sunk, and comes back halfway through his rise.
    func setGardenVisible(_ visible: Bool) {
        guard visible != gardenVisible else { return }
        gardenVisible = visible
        gardenLayer.removeAnimation(forKey: "visibility")
        gardenLayer.opacity = visible ? 1 : 0
        let delay = visible ? transitionDuration / 2 : transitionDuration
        guard delay > 0 else { return }
        let hold = CABasicAnimation(keyPath: "opacity")
        hold.fromValue = visible ? 0 : 1
        hold.toValue = hold.fromValue
        hold.duration = delay
        gardenLayer.add(hold, forKey: "visibility")
    }

    /// Shows a state or action by name, applying the pack's fallbacks. When
    /// the skin has an in-between clip for this switch, it plays once first
    /// and the new clip takes over when it ends, all scheduled in Core
    /// Animation (no timers).
    func show(_ name: String) {
        let (resolvedName, clip) = pack.resolve(name, outfit: outfit)
        guard resolvedName != currentClip else { return }
        let previous = currentClip
        currentClip = resolvedName
        transitionDuration = 0

        let frames = self.frames(for: "\(resolvedName)#\(outfit ?? "")", clip: clip)
        layer.removeAnimation(forKey: "transition")
        layer.removeAnimation(forKey: "frames")
        layer.contents = clip.loops ? frames.first : frames.last

        var start = layer.convertTime(CACurrentMediaTime(), from: nil)
        if let previous, let between = pack.transition(from: previous, to: resolvedName, outfit: outfit) {
            let inBetween = self.frames(for: "\(previous)>\(resolvedName)#\(outfit ?? "")", clip: between)
            if !inBetween.isEmpty {
                let animation = keyframes(inBetween, fps: between.fps)
                animation.beginTime = start
                layer.add(animation, forKey: "transition")
                start += animation.duration
                transitionDuration = animation.duration
            }
        }
        guard frames.count > 1 || layer.animation(forKey: "transition") != nil else { return }

        // Added after the in-between, so it wins once it begins.
        let animation = keyframes(frames, fps: clip.fps)
        animation.beginTime = start
        if clip.loops {
            animation.repeatCount = .infinity
        } else {
            // Play once and hold the last frame (e.g. `unplug`).
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
        }
        layer.add(animation, forKey: "frames")
    }

    private func keyframes(_ frames: [CGImage], fps: Double) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = frames
        animation.calculationMode = .discrete
        // Discrete mode needs one more key time than values for equal slots.
        animation.keyTimes = (0...frames.count).map { NSNumber(value: Double($0) / Double(frames.count)) }
        animation.duration = Double(frames.count) / fps
        return animation
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

        let animation = keyframes(frames, fps: clip.fps)
        let duration = animation.duration
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
