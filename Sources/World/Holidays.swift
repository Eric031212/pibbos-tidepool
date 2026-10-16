import Foundation

/// Holidays Pibbo dresses up for (CLAUDE.md Section 10): a bundled table, per
/// region, no remote updates. The region is the user's region setting
/// (`Locale.current.region`), not their physical location.
public enum Holiday: String, Sendable, CaseIterable {
    case halloween, christmas, newYear, lunarNewYear
}

public enum Holidays {
    /// Regions that celebrate the Lunar New Year.
    static let lunarNewYearRegions: Set<String> = ["CN", "TW", "HK", "MO", "SG", "MY", "KR", "VN"]

    /// The holiday to dress up for on `date`, if any. `region` is an ISO
    /// 3166 code such as "US" or "CN"; `timeZone` decides the local date.
    public static func current(on date: Date, region: String?, timeZone: TimeZone = .current) -> Holiday? {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        let parts = gregorian.dateComponents([.month, .day], from: date)
        guard let month = parts.month, let day = parts.day else { return nil }

        if let region, lunarNewYearRegions.contains(region.uppercased()), isLunarNewYear(date, timeZone: timeZone) {
            return .lunarNewYear
        }
        switch (month, day) {
        case (12, 31), (1, 1), (1, 2): return .newYear
        case (12, 20...26): return .christmas
        case (10, 25...31): return .halloween
        default: return nil
        }
    }

    /// From Lunar New Year's Eve to the 6th day of the first lunar month.
    /// (A leap first month, the only way "month 1" could be ambiguous, last
    /// happened in 1651 and next in 2262, so it is not checked; the
    /// `.isLeapMonth` component needs macOS 14 anyway.)
    static func isLunarNewYear(_ date: Date, timeZone: TimeZone) -> Bool {
        var chinese = Calendar(identifier: .chinese)
        chinese.timeZone = timeZone
        func isFirstWeek(_ d: Date) -> Bool {
            let c = chinese.dateComponents([.month, .day], from: d)
            return c.month == 1 && (1...6).contains(c.day ?? 0)
        }
        guard !isFirstWeek(date) else { return true }
        // New Year's Eve: tomorrow is the first day of the first month.
        guard let tomorrow = chinese.date(byAdding: .day, value: 1, to: date) else { return false }
        let c = chinese.dateComponents([.month, .day], from: tomorrow)
        return c.month == 1 && c.day == 1
    }
}
