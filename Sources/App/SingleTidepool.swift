import AppKit

/// Keeps exactly one Pibbo on screen and carries data over from before the
/// v1.0 rename (bundle ID `com.tidepool.app` → `io.github.eric031212.pibbostidepool`).
enum SingleTidepool {
    static let legacyBundleID = "com.tidepool.app"

    /// Keys whose values survive the rename. The login-item flag is left out
    /// on purpose: the new bundle ID has to register itself once.
    private static let carriedKeys = ["firstLaunchDate", "nextBottle", "lastCoordinate", "shorePosition"]
    private static let migratedKey = "migratedFromLegacyBundleID"

    /// False when another copy of this version is already running (this one
    /// should quit). An old pre-1.0 copy still running is stopped instead.
    static func claim() -> Bool {
        let me = NSRunningApplication.current
        let twins = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        if twins.contains(where: { $0.processIdentifier != me.processIdentifier }) { return false }
        // A plain kill, not an Apple Event: no Automation prompt (Section 8).
        NSRunningApplication.runningApplications(withBundleIdentifier: legacyBundleID).forEach { $0.forceTerminate() }
        return true
    }

    /// Copies the old preferences once, so an existing garden keeps its age.
    static func migrateLegacyDefaults() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migratedKey) else { return }
        defaults.set(true, forKey: migratedKey)
        guard let legacy = UserDefaults(suiteName: legacyBundleID) else { return }
        for key in carriedKeys where defaults.object(forKey: key) == nil {
            if let value = legacy.object(forKey: key) { defaults.set(value, forKey: key) }
        }
    }
}
