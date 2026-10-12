// Spike 3: transparent window.
// A borderless, non-activating, clear NSPanel in the bottom-right corner of the
// main display, showing one static placeholder frame at integer scale. Logs
// hover, clicks, focus, occlusion, Space changes and Dock/visibleFrame changes.
// The window has a transparent margin left of and above the sprite, outlined by
// a thin dashed line, to test whether clicks there pass through to the app
// behind. Click Pibbo for a menu with test toggles.

import AppKit
import QuartzCore

setvbuf(stdout, nil, _IOLBF, 0)

let timestampFormatter = ISO8601DateFormatter()
timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

func log(_ message: String) {
    print("[\(timestampFormatter.string(from: Date()))] \(message)")
}

func frontmostName() -> String {
    NSWorkspace.shared.frontmostApplication?.localizedName ?? "<none>"
}

// MARK: - Sprite

let frameSize = 16
let scale: CGFloat = 4
let spriteSide = CGFloat(frameSize) * scale   // 64 pt
let margin: CGFloat = 32                      // transparent test area
let chillRow = 2

let sheetPath = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("-") }) ?? ""
guard let sheet = NSImage(contentsOfFile: sheetPath)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let chillFrame = sheet.cropping(to: CGRect(x: 0, y: chillRow * frameSize, width: frameSize, height: frameSize)) else {
    print("Could not load sprite sheet at '\(sheetPath)'. Pass the path to sprites.png as the first argument.")
    exit(1)
}

// MARK: - View

final class PetView: NSView {
    let spriteLayer = CALayer()
    let outlineLayer = CAShapeLayer()
    var spriteRect: CGRect { CGRect(x: margin, y: 0, width: spriteSide, height: spriteSide) }
    var onSpriteClick: ((NSEvent) -> Void)?

    init(frame: NSRect, sprite: CGImage) {
        super.init(frame: frame)
        wantsLayer = true
        let root = CALayer()
        layer = root

        spriteLayer.frame = spriteRect
        spriteLayer.contents = sprite
        spriteLayer.magnificationFilter = .nearest
        root.addSublayer(spriteLayer)

        outlineLayer.path = CGPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5), transform: nil)
        outlineLayer.fillColor = nil
        outlineLayer.strokeColor = NSColor.systemPink.withAlphaComponent(0.7).cgColor
        outlineLayer.lineWidth = 1
        outlineLayer.lineDashPattern = [3, 3]
        root.addSublayer(outlineLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let backingScale = window?.backingScaleFactor ?? 2
        spriteLayer.contentsScale = backingScale
        outlineLayer.contentsScale = backingScale
        log("backingScaleFactor=\(backingScale): one sprite pixel = \(scale)pt = \(scale * backingScale) device px")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    func where_(_ event: NSEvent) -> String {
        let point = convert(event.locationInWindow, from: nil)
        return "at \(Int(point.x)),\(Int(point.y)) \(spriteRect.contains(point) ? "(on sprite)" : "(transparent margin)")"
    }

    override func mouseEntered(with event: NSEvent) { log("HOVER entered \(where_(event))  frontmost=\(frontmostName())") }
    override func mouseExited(with event: NSEvent) { log("HOVER exited \(where_(event))") }

    var lastMovedRegion: Bool?
    override func mouseMoved(with event: NSEvent) {
        let onSprite = spriteRect.contains(convert(event.locationInWindow, from: nil))
        if onSprite != lastMovedRegion { log("MOVE now \(where_(event))") }
        lastMovedRegion = onSprite
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        log("CLICK received \(where_(event))  frontmost=\(frontmostName()) NSApp.isActive=\(NSApp.isActive)")
        if spriteRect.contains(convert(event.locationInWindow, from: nil)) { onSpriteClick?(event) }
    }
}

// MARK: - Panel

let windowSize = NSSize(width: spriteSide + margin, height: spriteSide + margin)
let petPanel = NSPanel(contentRect: NSRect(origin: .zero, size: windowSize),
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered, defer: false)
petPanel.isOpaque = false
petPanel.backgroundColor = .clear
petPanel.hasShadow = false
petPanel.level = .floating
petPanel.isFloatingPanel = true
petPanel.hidesOnDeactivate = false
petPanel.becomesKeyOnlyIfNeeded = true
petPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

let petView = PetView(frame: NSRect(origin: .zero, size: windowSize), sprite: chillFrame)
petPanel.contentView = petView

func describeBehavior() -> String {
    let aux = petPanel.collectionBehavior.contains(.fullScreenAuxiliary)
    let levelName = petPanel.level == .floating ? "floating" : petPanel.level == .statusBar ? "statusBar" : "\(petPanel.level.rawValue)"
    return "level=\(levelName) fullScreenAuxiliary=\(aux)"
}

// MARK: - Position (bottom-right of the main display's visible frame)

var lastVisibleFrame = NSRect.zero

func dockDescription(_ screen: NSScreen) -> String {
    let full = screen.frame, visible = screen.visibleFrame
    var parts: [String] = []
    if visible.minY > full.minY { parts.append("bottom (\(Int(visible.minY - full.minY))pt)") }
    if visible.minX > full.minX { parts.append("left (\(Int(visible.minX - full.minX))pt)") }
    if visible.maxX < full.maxX { parts.append("right (\(Int(full.maxX - visible.maxX))pt)") }
    return parts.isEmpty ? "not reserving space (auto-hide?)" : parts.joined(separator: ", ")
}

func reposition(reason: String) {
    guard let screen = NSScreen.screens.first else { return }
    let visible = screen.visibleFrame
    lastVisibleFrame = visible
    petPanel.setFrameOrigin(NSPoint(x: visible.maxX - windowSize.width, y: visible.minY))
    log("POSITION (\(reason)) screen=\(screen.frame) visible=\(visible) dock=\(dockDescription(screen)) -> window=\(petPanel.frame)")
}

// MARK: - Menu

final class MenuTarget: NSObject {
    @objc func toggleOutline() {
        petView.outlineLayer.isHidden.toggle()
        log("MENU outline \(petView.outlineLayer.isHidden ? "hidden" : "shown")")
    }
    @objc func toggleAux() {
        if petPanel.collectionBehavior.contains(.fullScreenAuxiliary) {
            petPanel.collectionBehavior.remove(.fullScreenAuxiliary)
        } else {
            petPanel.collectionBehavior.insert(.fullScreenAuxiliary)
        }
        log("MENU \(describeBehavior())")
    }
    @objc func toggleLevel() {
        petPanel.level = petPanel.level == .floating ? .statusBar : .floating
        log("MENU \(describeBehavior())")
    }
    @objc func quit() {
        log("MENU quit")
        NSApp.terminate(nil)
    }
}
let menuTarget = MenuTarget()

petView.onSpriteClick = { event in
    let menu = NSMenu()
    func add(_ title: String, _ action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = menuTarget
        menu.addItem(item)
    }
    add(petView.outlineLayer.isHidden ? "show outline" : "hide outline", #selector(MenuTarget.toggleOutline))
    add("fullScreenAuxiliary: \(petPanel.collectionBehavior.contains(.fullScreenAuxiliary) ? "on → off" : "off → on")", #selector(MenuTarget.toggleAux))
    add("level: \(petPanel.level == .floating ? "floating → statusBar" : "statusBar → floating")", #selector(MenuTarget.toggleLevel))
    menu.addItem(.separator())
    add("bye 👋", #selector(MenuTarget.quit))

    log("MENU open  frontmost=\(frontmostName()) NSApp.isActive=\(NSApp.isActive) petPanel.isKey=\(petPanel.isKeyWindow)")
    menu.popUp(positioning: nil, at: petView.convert(event.locationInWindow, from: nil), in: petView)
    log("MENU closed frontmost=\(frontmostName()) NSApp.isActive=\(NSApp.isActive) petPanel.isKey=\(petPanel.isKeyWindow)")
}

// MARK: - Observers

NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: petPanel, queue: .main) { _ in
    log("OCCLUSION visible=\(petPanel.occlusionState.contains(.visible)) onActiveSpace=\(petPanel.isOnActiveSpace)  frontmost=\(frontmostName())")
}
NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
    reposition(reason: "screen parameters changed")
}
let workspaceCenter = NSWorkspace.shared.notificationCenter
/// Fullscreen-Space probe: on a normal desktop the main display has an on-screen
/// desktop-level window (owner "Wallpaper", plus Finder's desktop icons); a
/// fullscreen Space should have none. Reads only layer, owner name and bounds.
func desktopProbe() -> String {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))
    let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
    let mainHeight = NSScreen.screens.first?.frame.height ?? 0
    var found: [String] = []
    for window in windows {
        let layer = window[kCGWindowLayer as String] as? Int ?? 0
        guard layer <= iconLevel, layer >= desktopLevel - 10,
              let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDict),
              bounds.origin == .zero, bounds.height >= mainHeight else { continue }
        found.append("\(window[kCGWindowOwnerName as String] as? String ?? "?")@\(layer - desktopLevel)")
    }
    return "desktopWindows=\(found.isEmpty ? "NONE -> fullscreen Space" : found.joined(separator: ","))"
}

workspaceCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
    log("SPACE changed  onActiveSpace=\(petPanel.isOnActiveSpace) visible=\(petPanel.occlusionState.contains(.visible)) frontmost=\(frontmostName())  \(desktopProbe())")
    for delay in [0.5, 1.5] {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { log("  +\(delay)s \(desktopProbe())") }
    }
}
workspaceCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
    let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    log("ACTIVATE \(app?.localizedName ?? "?")")
}
DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
    log("LOCKED  visible=\(petPanel.occlusionState.contains(.visible))")
}
DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
    log("UNLOCKED  visible=\(petPanel.occlusionState.contains(.visible))")
}

// Spike-only cross-check: report a visibleFrame change that no event announced.
let tick = Timer(timeInterval: 5, repeats: true) { _ in
    guard let visible = NSScreen.screens.first?.visibleFrame, visible != lastVisibleFrame else { return }
    log("!!! visibleFrame changed WITHOUT an event")
    reposition(reason: "tick")
}
tick.tolerance = 1
RunLoop.main.add(tick, forMode: .common)

// MARK: - Variants (--variants)
// Small labelled squares with different window configurations, in a row left
// of Pibbo, to find one that macOS keeps off fullscreen Spaces by itself.

struct Variant {
    let label: String
    let summary: String
    let make: () -> NSWindow
}

func borderlessPanel(level: NSWindow.Level, behavior: NSWindow.CollectionBehavior) -> NSWindow {
    let window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    window.isFloatingPanel = level == .floating
    window.hidesOnDeactivate = false
    window.level = level
    window.collectionBehavior = behavior
    return window
}

func borderlessWindow(level: NSWindow.Level, behavior: NSWindow.CollectionBehavior) -> NSWindow {
    let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
    window.level = level
    window.collectionBehavior = behavior
    return window
}

let variants: [Variant] = [
    Variant(label: "A", summary: "NSPanel nonactivating, floating, allSpaces+stationary (= Pibbo)") {
        borderlessPanel(level: .floating, behavior: [.canJoinAllSpaces, .stationary]) },
    Variant(label: "B", summary: "NSPanel nonactivating, normal level, allSpaces+stationary") {
        borderlessPanel(level: .normal, behavior: [.canJoinAllSpaces, .stationary]) },
    Variant(label: "C", summary: "NSWindow borderless, floating, allSpaces+stationary") {
        borderlessWindow(level: .floating, behavior: [.canJoinAllSpaces, .stationary]) },
    Variant(label: "D", summary: "NSWindow borderless, normal level, allSpaces+stationary") {
        borderlessWindow(level: .normal, behavior: [.canJoinAllSpaces, .stationary]) },
    Variant(label: "E", summary: "NSPanel nonactivating, floating, allSpaces only") {
        borderlessPanel(level: .floating, behavior: [.canJoinAllSpaces]) },
    Variant(label: "F", summary: "NSPanel nonactivating, floating, default behavior (one Space)") {
        borderlessPanel(level: .floating, behavior: []) },
]

var variantWindows: [NSWindow] = []

func showVariants() {
    guard let visible = NSScreen.screens.first?.visibleFrame else { return }
    let side: CGFloat = 36, gap: CGFloat = 6
    for (index, variant) in variants.enumerated() {
        let window = variant.make()
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        let x = visible.maxX - windowSize.width - CGFloat(variants.count - index) * (side + gap)
        window.setFrame(NSRect(x: x, y: visible.minY, width: side, height: side), display: false)

        let label = NSTextField(labelWithString: variant.label)
        label.font = .boldSystemFont(ofSize: 20)
        label.textColor = .white
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 6, width: side, height: 24)
        let box = NSView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor(calibratedHue: CGFloat(index) / CGFloat(variants.count), saturation: 0.6, brightness: 0.8, alpha: 1).cgColor
        box.layer?.cornerRadius = 6
        box.addSubview(label)
        window.contentView = box

        NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { _ in
            log("VARIANT \(variant.label) visible=\(window.occlusionState.contains(.visible)) onActiveSpace=\(window.isOnActiveSpace)")
        }
        window.orderFrontRegardless()
        variantWindows.append(window)
        log("VARIANT \(variant.label): \(variant.summary)")
    }
}

// MARK: - Start

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
reposition(reason: "launch")
petPanel.orderFrontRegardless()
if CommandLine.arguments.contains("--variants") { showVariants() }
log("Spike 3 started. pid=\(ProcessInfo.processInfo.processIdentifier) \(describeBehavior()) frontmost=\(frontmostName())  \(desktopProbe())")
app.run()
