// Spike 4: pixel animation rendering.
// Plays the placeholder skin's clips as CAKeyframeAnimations on a layer's
// `contents` (discrete, nearest-neighbour, integer scale) so the system render
// server animates them and this process can stay idle. The process has no
// timers. Click Pibbo for a menu of clips; the same commands can be sent by a
// test script as the distributed notification "com.tidepool.spike.anim"
// (object = command) so CPU, wakeups and memory can be measured hands-free.
// Commands: <clip name>, "music+bob", "still", "pause", "resume", "quit".

import AppKit
import QuartzCore

setvbuf(stdout, nil, _IOLBF, 0)

let timestampFormatter = ISO8601DateFormatter()
timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

func log(_ message: String) {
    print("[\(timestampFormatter.string(from: Date()))] \(message)")
}

// MARK: - Skin

struct Clip: Decodable {
    let row: Int
    let frames: Int
    let fps: Double
}

struct Manifest: Decodable {
    let frameSize: Int
    let states: [String: Clip]
    let actions: [String: Clip]?
}

let packPath = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("-") }) ?? ""
let packURL = URL(fileURLWithPath: packPath)
guard let manifestData = try? Data(contentsOf: packURL.appendingPathComponent("manifest.json")),
      let manifest = try? JSONDecoder().decode(Manifest.self, from: manifestData),
      let sheet = NSImage(contentsOf: packURL.appendingPathComponent("sprites.png"))?
          .cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("Could not load the skin pack at '\(packPath)'. Pass the pack folder as the first argument.")
    exit(1)
}

let clips: [String: Clip] = manifest.states.merging(manifest.actions ?? [:]) { state, _ in state }
let clipOrder = ["hidden", "peek", "chill", "music", "sleep", "submerged"].filter { clips[$0] != nil }

/// Crops every frame of every clip once, up front.
let clipFrames: [String: [CGImage]] = clips.mapValues { clip in
    (0..<clip.frames).compactMap { index in
        sheet.cropping(to: CGRect(x: index * manifest.frameSize, y: clip.row * manifest.frameSize,
                                  width: manifest.frameSize, height: manifest.frameSize))
    }
}

// MARK: - Layer and panel

let scale: CGFloat = 4
let spriteSide = CGFloat(manifest.frameSize) * scale
let bobHeight = scale  // one sprite pixel
let windowSize = NSSize(width: spriteSide, height: spriteSide + bobHeight)

let spriteLayer = CALayer()
spriteLayer.frame = CGRect(x: 0, y: 0, width: spriteSide, height: spriteSide)
spriteLayer.magnificationFilter = .nearest
spriteLayer.actions = ["contents": NSNull(), "position": NSNull()]  // no implicit fades

final class PetView: NSView {
    var onClick: ((NSEvent) -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if spriteLayer.frame.contains(convert(event.locationInWindow, from: nil)) { onClick?(event) }
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        spriteLayer.contentsScale = window?.backingScaleFactor ?? 2
    }
}

let petView = PetView(frame: NSRect(origin: .zero, size: windowSize))
petView.wantsLayer = true
petView.layer = CALayer()
petView.layer?.addSublayer(spriteLayer)

let panel = NSPanel(contentRect: NSRect(origin: .zero, size: windowSize),
                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = false
panel.level = .floating
panel.isFloatingPanel = true
panel.hidesOnDeactivate = false
panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
panel.contentView = petView

func reposition() {
    guard let visible = NSScreen.screens.first?.visibleFrame else { return }
    panel.setFrameOrigin(NSPoint(x: visible.maxX - windowSize.width, y: visible.minY))
}

// MARK: - Playback

var current = "chill"

func frameAnimation(_ frames: [CGImage], fps: Double) -> CAKeyframeAnimation {
    let animation = CAKeyframeAnimation(keyPath: "contents")
    animation.values = frames
    animation.calculationMode = .discrete
    // Discrete mode: one more key time than values, so every frame gets an equal slot.
    animation.keyTimes = (0...frames.count).map { NSNumber(value: Double($0) / Double(frames.count)) }
    animation.duration = Double(frames.count) / fps
    animation.repeatCount = .infinity
    return animation
}

/// Gentle bob for music: up one sprite pixel and back, in whole-pixel steps.
func bobAnimation() -> CAKeyframeAnimation {
    let base = spriteLayer.position.y
    let animation = CAKeyframeAnimation(keyPath: "position.y")
    animation.values = [base, base + bobHeight]
    animation.calculationMode = .discrete
    animation.keyTimes = [0, 0.5, 1]
    animation.duration = 60.0 / 78.0 * 2  // two beats at 78 bpm
    animation.repeatCount = .infinity
    return animation
}

func play(_ command: String) {
    switch command {
    case "pause":
        let layer = petView.layer!
        layer.timeOffset = layer.convertTime(CACurrentMediaTime(), from: nil)
        layer.speed = 0
        log("PAUSE (layer.speed = 0) on \(current)")
        return
    case "resume":
        let layer = petView.layer!
        let pausedAt = layer.timeOffset
        layer.speed = 1
        layer.timeOffset = 0
        layer.beginTime = 0
        layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedAt
        log("RESUME \(current)")
        return
    case "quit":
        log("QUIT")
        NSApp.terminate(nil)
        return
    default:
        break
    }

    spriteLayer.removeAllAnimations()
    let clipName = command == "music+bob" ? "music" : command == "still" ? "chill" : command
    guard let frames = clipFrames[clipName], let clip = clips[clipName], !frames.isEmpty else {
        log("unknown command '\(command)'")
        return
    }
    spriteLayer.contents = frames[0]
    if command != "still", frames.count > 1 {
        spriteLayer.add(frameAnimation(frames, fps: clip.fps), forKey: "frames")
    }
    if command == "music+bob" {
        spriteLayer.add(bobAnimation(), forKey: "bob")
    }
    current = command
    log("PLAY \(command)  (\(frames.count) frames @ \(clip.fps) fps\(command == "still" ? ", animation off" : ""))")
}

// MARK: - Menu and remote control

final class MenuTarget: NSObject {
    @objc func choose(_ item: NSMenuItem) { play(item.representedObject as! String) }
}
let menuTarget = MenuTarget()

petView.onClick = { event in
    let menu = NSMenu()
    for command in clipOrder + ["music+bob", "still", "pause", "resume", "quit"] {
        let item = NSMenuItem(title: command == current ? "• \(command)" : command,
                              action: #selector(MenuTarget.choose(_:)), keyEquivalent: "")
        item.target = menuTarget
        item.representedObject = command
        menu.addItem(item)
    }
    menu.popUp(positioning: nil, at: petView.convert(event.locationInWindow, from: nil), in: petView)
}

DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.tidepool.spike.anim"),
                                                    object: nil, queue: .main) { note in
    if let command = note.object as? String { play(command) }
}
NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                       object: nil, queue: .main) { _ in reposition() }

// MARK: - Start

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
reposition()
play("chill")
panel.orderFrontRegardless()
log("Spike 4 started. pid=\(ProcessInfo.processInfo.processIdentifier) clips=\(clipOrder)")
app.run()
