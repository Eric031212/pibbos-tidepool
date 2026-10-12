// Spike 2: user state signals.
// Reads idle time, frontmost app, fullscreen, screen lock and sleep using only
// public APIs that should need no permission. Prints the state at launch and
// every event afterwards. A 5 s timer prints idle time and cross-checks that
// no fullscreen/lock change slipped past the events (spike only; the app
// would poll idle every ~30 s and rely on events for everything else).

import AppKit
import CoreGraphics

setvbuf(stdout, nil, _IOLBF, 0)

let timestampFormatter = ISO8601DateFormatter()
timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

func log(_ message: String) {
    print("[\(timestampFormatter.string(from: Date()))] \(message)")
}

// MARK: - Idle time

/// kCGAnyInputEventType: seconds since the last input event of any type.
let anyInputEvent = CGEventType(rawValue: ~0)!

func idleReport() -> String {
    let combined = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInputEvent)
    let hid = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInputEvent)
    return String(format: "idle combined=%.1fs hid=%.1fs", combined, hid)
}

// MARK: - Frontmost app

func describe(_ app: NSRunningApplication?) -> String {
    guard let app else { return "<none>" }
    return "\(app.localizedName ?? "?") bundle=\(app.bundleIdentifier ?? "?") pid=\(app.processIdentifier)"
}

// MARK: - Fullscreen

/// Checks whether a layer-0 window of the frontmost app covers the whole main
/// display. Reads only owner PID, layer and bounds. Window names are never
/// printed; we only count how many windows expose one, because names are
/// visible only with Screen Recording permission (which we must not have).
func fullscreenCheck(verbose: Bool) -> Bool {
    guard let app = NSWorkspace.shared.frontmostApplication,
          let screen = NSScreen.screens.first else { return false }
    let screenSize = screen.frame.size
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []

    let namedOwners = windows.filter { $0[kCGWindowName as String] != nil }
        .map { $0[kCGWindowOwnerName as String] as? String ?? "?" }
    let named = "\(namedOwners.count) (owners: \(namedOwners.joined(separator: ", ")))"
    var isFullscreen = false
    var lines: [String] = []
    for window in windows where (window[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier {
        let layer = window[kCGWindowLayer as String] as? Int ?? -1
        guard let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDict) else { continue }
        let covers = layer == 0 && bounds.origin == .zero
            && bounds.width >= screenSize.width && bounds.height >= screenSize.height
        if covers { isFullscreen = true }
        lines.append("      layer=\(layer) bounds=\(Int(bounds.minX)),\(Int(bounds.minY)) \(Int(bounds.width))x\(Int(bounds.height))\(covers ? "  <- covers screen" : "")")
    }
    if verbose {
        log("  fullscreen=\(isFullscreen)  main screen=\(Int(screenSize.width))x\(Int(screenSize.height))  on-screen windows=\(windows.count), with a readable name=\(named)")
        lines.forEach { print($0) }
    }
    return isFullscreen
}

// MARK: - Lock state

/// CGSessionCopyCurrentDictionary is public; the "CGSSessionScreenIsLocked"
/// key is undocumented. Only these two keys are printed (the dictionary also
/// holds the user name, which we do not want in logs).
func lockReport() -> (locked: Bool, text: String) {
    guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else {
        return (false, "CGSessionCopyCurrentDictionary = nil")
    }
    let locked = (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
    let onConsole = session[kCGSessionOnConsoleKey as String] as? Bool
    return (locked, "screenIsLocked=\(locked) onConsole=\(onConsole.map(String.init) ?? "nil") sessionKeys=\(session.keys.sorted())")
}

// MARK: - Observers

var lastFullscreen = false
var lastLocked = false

func recheckFullscreen(reason: String) {
    let now = fullscreenCheck(verbose: true)
    if now != lastFullscreen { log("  >>> fullscreen changed: \(lastFullscreen) -> \(now) (\(reason))") }
    lastFullscreen = now
}

let workspaceCenter = NSWorkspace.shared.notificationCenter

workspaceCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
    let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    log("EVENT didActivateApplication: \(describe(app))")
    recheckFullscreen(reason: "app activated")
}

workspaceCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
    log("EVENT activeSpaceDidChange  frontmost: \(describe(NSWorkspace.shared.frontmostApplication))")
    recheckFullscreen(reason: "space changed")
}

let plainWorkspaceEvents: [(Notification.Name, String)] = [
    (NSWorkspace.screensDidSleepNotification, "screensDidSleep"),
    (NSWorkspace.screensDidWakeNotification, "screensDidWake"),
    (NSWorkspace.willSleepNotification, "willSleep"),
    (NSWorkspace.didWakeNotification, "didWake"),
    (NSWorkspace.sessionDidResignActiveNotification, "sessionDidResignActive"),
    (NSWorkspace.sessionDidBecomeActiveNotification, "sessionDidBecomeActive"),
]
for (name, label) in plainWorkspaceEvents {
    workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { _ in
        log("EVENT \(label)  \(lockReport().text)")
    }
}

let distributedNames = [
    "com.apple.screenIsLocked",
    "com.apple.screenIsUnlocked",
    "com.apple.screensaver.didstart",
    "com.apple.screensaver.willstop",
    "com.apple.screensaver.didstop",
]
for name in distributedNames {
    DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name), object: nil, queue: .main) { note in
        let keys = note.userInfo.map { $0.keys.map { "\($0)" }.sorted() } ?? []
        log("EVENT \(name)  userInfoKeys=\(keys)  \(lockReport().text)")
        lastLocked = lockReport().locked
    }
}

NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
    log("EVENT didChangeScreenParameters")
    recheckFullscreen(reason: "screen parameters changed")
}

// MARK: - Start

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

log("Spike 2 started. pid=\(ProcessInfo.processInfo.processIdentifier) bundle=\(Bundle.main.bundleIdentifier ?? "<none: not running as .app>")")
log("INITIAL \(idleReport())")
log("INITIAL frontmost: \(describe(NSWorkspace.shared.frontmostApplication))")
lastFullscreen = fullscreenCheck(verbose: true)
let initialLock = lockReport()
lastLocked = initialLock.locked
log("INITIAL \(initialLock.text)")

let tick = Timer(timeInterval: 5, repeats: true) { _ in
    log("tick \(idleReport())")
    // Cross-checks: report changes that no event announced.
    let fullscreen = fullscreenCheck(verbose: false)
    if fullscreen != lastFullscreen {
        log("  !!! fullscreen changed WITHOUT an event: \(lastFullscreen) -> \(fullscreen)")
        recheckFullscreen(reason: "tick")
    }
    let locked = lockReport().locked
    if locked != lastLocked {
        log("  !!! lock changed WITHOUT an event: \(lastLocked) -> \(locked)")
        lastLocked = locked
    }
}
tick.tolerance = 1
RunLoop.main.add(tick, forMode: .common)

app.run()
