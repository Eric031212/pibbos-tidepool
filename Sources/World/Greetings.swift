import Foundation

/// Moments when Pibbo notices *you* (v1.4): the first hello, good morning,
/// welcome back after a while away, and a late-night "night owl?". Pure rules;
/// the platform tells when you came back and keeps `GreetingMemory`.
public enum Greeting: Equatable, Sendable {
    /// The very first launch.
    case hello
    /// The first time you're here today, before noon (weather nil = unknown).
    case morning(Weather?)
    /// The same on a Saturday or Sunday.
    case weekend(saturday: Bool)
    /// Back after a couple of hours away.
    case welcomeBack
    /// Still up late.
    case nightOwl

    /// What Pibbo does while he says it.
    public var action: String? { self == .nightOwl ? "cocoa" : nil }
}

/// What has been said already, so each moment stays rare. Days start at 4:00,
/// so a night owl after midnight still belongs to the evening before.
public struct GreetingMemory: Equatable, Sendable {
    /// Day key ("2026-11-15") of the last morning greeting.
    public var morningDay: String?
    public var welcomeBackDay: String?
    public var welcomeBacksThatDay = 0
    public var nightOwlDay: String?

    public init(morningDay: String? = nil, welcomeBackDay: String? = nil, welcomeBacksThatDay: Int = 0, nightOwlDay: String? = nil) {
        self.morningDay = morningDay
        self.welcomeBackDay = welcomeBackDay
        self.welcomeBacksThatDay = welcomeBacksThatDay
        self.nightOwlDay = nightOwlDay
    }
}

public enum Greetings {
    /// Away at least this long, then back: a new morning (if it's a new day).
    public static let morningAway: TimeInterval = 4 * 3600
    /// Away at least this long, then back: welcome back.
    public static let welcomeAway: TimeInterval = 2 * 3600
    public static let welcomeBacksPerDay = 2

    /// The day a moment belongs to: days start at 4:00.
    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let shifted = date.addingTimeInterval(-4 * 3600)
        let c = calendar.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// You're here at `now`, after being away `awayFor` seconds (nil: the app
    /// just started, so we don't know). Returns what to say, if anything, and
    /// the memory to keep.
    public static func onReturn(at now: Date, awayFor: TimeInterval?, firstLaunch: Bool, weather: Weather?,
                                memory: GreetingMemory, calendar: Calendar) -> (Greeting?, GreetingMemory) {
        var memory = memory
        let today = dayKey(now, calendar: calendar)
        let hour = calendar.component(.hour, from: now)
        if firstLaunch {
            memory.morningDay = today  // the hello is today's greeting
            return (.hello, memory)
        }
        let longAway = awayFor.map { $0 >= morningAway } ?? true
        if longAway && memory.morningDay != today && (4..<12).contains(hour) {
            memory.morningDay = today
            let weekday = calendar.component(.weekday, from: now)  // 1 = Sunday, 7 = Saturday
            if weekday == 1 || weekday == 7 { return (.weekend(saturday: weekday == 7), memory) }
            return (.morning(weather), memory)
        }
        if let awayFor, awayFor >= welcomeAway, (6..<23).contains(hour) {
            if memory.welcomeBackDay != today {
                memory.welcomeBackDay = today
                memory.welcomeBacksThatDay = 0
            }
            if memory.welcomeBacksThatDay < welcomeBacksPerDay {
                memory.welcomeBacksThatDay += 1
                if memory.morningDay != today { memory.morningDay = today }  // no "morning" after this today
                return (.welcomeBack, memory)
            }
        }
        return nightOwl(at: now, memory: memory, calendar: calendar)
    }

    /// You're active at `now`: late at night, once, Pibbo keeps you company.
    public static func nightOwl(at now: Date, memory: GreetingMemory, calendar: Calendar) -> (Greeting?, GreetingMemory) {
        var memory = memory
        let hour = calendar.component(.hour, from: now)
        guard hour >= 23 || hour < 4 else { return (nil, memory) }
        let night = dayKey(now, calendar: calendar)
        guard memory.nightOwlDay != night else { return (nil, memory) }
        memory.nightOwlDay = night
        return (.nightOwl, memory)
    }
}
