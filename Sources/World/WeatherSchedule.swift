import Foundation

/// When to ask MET Norway again (Section 8): every 1–3 hours, but never
/// before the forecast's `Expires`; half an hour after a failure.
public enum WeatherSchedule {
    public static func next(after now: Date, expires: Date?, failed: Bool, jitter: TimeInterval = 0) -> Date {
        if failed { return now.addingTimeInterval(30 * 60 + jitter) }
        let usual = min(max(expires ?? now, now.addingTimeInterval(3600)), now.addingTimeInterval(3 * 3600))
        // A later Expires wins over the 3-hour cap: the data isn't new before then.
        return max(usual, expires ?? usual).addingTimeInterval(jitter)
    }
}
