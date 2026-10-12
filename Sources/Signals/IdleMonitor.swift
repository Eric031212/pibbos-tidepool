import CoreGraphics
import Foundation

/// Samples seconds since the last keyboard/mouse input (spike 2: no
/// permission). The only polling in the app: every 30 s with tolerance, and
/// stopped while Pibbo is suspended.
final class IdleMonitor {
    var onSample: ((TimeInterval) -> Void)?
    private var timer: Timer?
    private let interval: TimeInterval = 30

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.sample() }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        sample()  // after `timer` is set: the callback may call start() again
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        // kCGAnyInputEventType
        let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        onSample?(seconds)
    }
}
