import AppKit
import Brain

/// Screen lock, display sleep and system sleep (spike 2: no permission).
/// `willSleep` can arrive without a real sleep, so it only ever means "pause".
final class SessionMonitor {
    var onEvent: ((BrainEvent) -> Void)?
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    /// Lock state right now. `CGSSessionScreenIsLocked` is undocumented; a
    /// missing key means unlocked, and the notifications take over afterwards.
    static var isLockedNow: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return session?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    func start() {
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, "com.apple.screenIsLocked", .suspended(.locked))
        observe(distributed, "com.apple.screenIsUnlocked", .resumed(.locked))

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification.rawValue, .suspended(.asleep))
        observe(workspace, NSWorkspace.didWakeNotification.rawValue, .resumed(.asleep))
        observe(workspace, NSWorkspace.screensDidSleepNotification.rawValue, .suspended(.asleep))
        observe(workspace, NSWorkspace.screensDidWakeNotification.rawValue, .resumed(.asleep))
    }

    private func observe(_ center: NotificationCenter, _ name: String, _ event: BrainEvent) {
        let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
            self?.onEvent?(event)
        }
        tokens.append((center, token))
    }

    deinit {
        tokens.forEach { center, token in center.removeObserver(token) }
    }
}
