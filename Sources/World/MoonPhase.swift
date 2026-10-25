import Foundation

/// How full the moon is, computed locally from the date (no network): the
/// mean synodic month counted from a known new moon. Off by up to about half
/// a day from the true phase, which is plenty for moonlight on a tide pool.
public enum MoonPhase {
    /// New moon of 2000-01-06 18:14 UTC.
    static let referenceNewMoon = Date(timeIntervalSince1970: 947_182_440)
    static let synodicMonth: TimeInterval = 29.530_588_853 * 86_400

    /// Days since the last new moon, 0..<29.53.
    public static func age(at date: Date) -> Double {
        let cycles = date.timeIntervalSince(referenceNewMoon) / synodicMonth
        return (cycles - cycles.rounded(.down)) * synodicMonth / 86_400
    }

    /// Lit fraction of the moon's disc: 0 = new moon, 1 = full moon.
    public static func illumination(at date: Date) -> Double {
        let angle = 2 * Double.pi * age(at: date) / (synodicMonth / 86_400)
        return (1 - cos(angle)) / 2
    }

    /// Illumination rounded to eighths, so the world only "changes" a few
    /// times a week rather than every second.
    public static func moonlight(at date: Date) -> Double {
        (illumination(at: date) * 8).rounded() / 8
    }
}
