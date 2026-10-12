import AppKit
import CoreGraphics

/// Detects whether a fullscreen Space is active on the main display (spike 3).
///
/// Reads only window layer, owner name and bounds from
/// `CGWindowListCopyWindowInfo` (never titles, so no Screen Recording
/// permission). A fullscreen Space has **no** full-screen Finder desktop-icon
/// window **and** a full-screen `WindowManager` window one level above the
/// desktop. Both must hold, so if a future macOS changes either marker the
/// probe reports "not fullscreen" and Pibbo simply stays visible.
/// Undocumented behaviour: re-verify on new macOS releases.
final class FullscreenProbe {
    var onChange: ((Bool) -> Void)?
    private(set) var isFullscreen = false
    private var token: NSObjectProtocol?
    private var pendingCheck: DispatchWorkItem?

    /// The window list is mid-transition when the Space change arrives.
    private let settleDelay: TimeInterval = 0.5

    func start() {
        isFullscreen = Self.probe()
        if isFullscreen { onChange?(true) }
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.scheduleCheck() }
    }

    private func scheduleCheck() {
        pendingCheck?.cancel()
        let check = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let now = Self.probe()
            guard now != self.isFullscreen else { return }
            self.isFullscreen = now
            self.onChange?(now)
        }
        pendingCheck = check
        DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay, execute: check)
    }

    static func probe() -> Bool {
        guard let main = NSScreen.screens.first else { return false }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))
        let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
        var hasDesktopIcons = false
        var hasFullscreenBackdrop = false
        for window in windows {
            guard let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.origin == .zero, bounds.height >= main.frame.height else { continue }
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            let owner = window[kCGWindowOwnerName as String] as? String
            if layer == iconLevel && owner == "Finder" { hasDesktopIcons = true }
            if layer == desktopLevel + 1 && owner == "WindowManager" { hasFullscreenBackdrop = true }
        }
        return !hasDesktopIcons && hasFullscreenBackdrop
    }

    deinit {
        if let token { NSWorkspace.shared.notificationCenter.removeObserver(token) }
    }
}
