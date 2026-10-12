import Foundation
import ServiceManagement

/// Registers Tidepool as a login item once, on the first launch (spike 6: no
/// prompt; macOS shows a one-time "Login Item Added" notification, accepted).
/// Never re-registers afterwards, so a user who turns it off in System
/// Settings stays turned off.
enum LaunchAtLogin {
    private static let didRegisterKey = "didRegisterLoginItem"

    static func registerOnFirstLaunch() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didRegisterKey) else { return }
        // Development builds run from DerivedData; don't register those paths.
        let path = Bundle.main.bundlePath
        let installed = path.hasPrefix("/Applications/")
            || path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path + "/")
        guard installed else { return }
        do {
            try SMAppService.mainApp.register()
            defaults.set(true, forKey: didRegisterKey)
        } catch {
            NSLog("Tidepool: login item registration failed: \(error)")
        }
    }
}
