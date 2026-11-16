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
    /// The first day of a new season (v2.0).
    case newSeason(Season)
    /// Day 100, then every year since the first launch (v2.0).
    case together(days: Int)
    /// The first snow of the winter (v2.0).
    case firstSnow

    /// What Pibbo does while he says it.
    public var action: String? {
        switch self {
        case .nightOwl, .firstSnow: return "cocoa"
        case .together: return "backfloat"  // on his back, a little heart rising
        case .newSeason(let season):
            switch season {
            case .spring: return "petal"
            case .summer: return "sunbathe"
            case .autumn: return "leaf"
            case .winter: return "cocoa"
            }
        default: return nil
        }
    }
}

/// What has been said already, so each moment stays rare. Days start at 4:00,
/// so a night owl after midnight still belongs to the evening before.
public struct GreetingMemory: Equatable, Sendable {
    /// Day key ("2026-11-15") of the last morning greeting.
    public var morningDay: String?
    public var welcomeBackDay: String?
    public var welcomeBacksThatDay = 0
    public var nightOwlDay: String?
    /// The season last seen (nil: never; the first sighting is only noted).
    public var season: String?
    /// The last "together" milestone celebrated, in days.
    public var milestone = 0
    /// Season key ("winter-2026") of the last first snow.
    public var firstSnowWinter: String?

    public init(morningDay: String? = nil, welcomeBackDay: String? = nil, welcomeBacksThatDay: Int = 0, nightOwlDay: String? = nil,
                season: String? = nil, milestone: Int = 0, firstSnowWinter: String? = nil) {
        self.morningDay = morningDay
        self.welcomeBackDay = welcomeBackDay
        self.welcomeBacksThatDay = welcomeBacksThatDay
        self.nightOwlDay = nightOwlDay
        self.season = season
        self.milestone = milestone
        self.firstSnowWinter = firstSnowWinter
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
                                memory: GreetingMemory, calendar: Calendar,
                                daysTogether: Int = 0, season: Season? = nil) -> (Greeting?, GreetingMemory) {
        var memory = memory
        let today = dayKey(now, calendar: calendar)
        let hour = calendar.component(.hour, from: now)
        if firstLaunch {
            memory.morningDay = today  // the hello is today's greeting
            if let season { memory.season = season.rawValue }
            return (.hello, memory)
        }
        let longAway = awayFor.map { $0 >= morningAway } ?? true
        if longAway && memory.morningDay != today && (4..<12).contains(hour) {
            memory.morningDay = today
            if let season {
                let (special, updated) = occasion(at: now, daysTogether: daysTogether, season: season, memory: memory)
                memory = updated
                if let special { return (special, memory) }
            }
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

    /// A milestone is only celebrated within this many days of it (an update
    /// arriving late doesn't throw a belated party).
    static let milestoneGrace = 7

    /// Day 100, 365, 730, … : the milestone `days` falls on (within the grace), if any.
    public static func milestone(forDay days: Int) -> Int? {
        let candidates = [100] + (1...50).map { $0 * 365 }
        return candidates.first { days >= $0 && days - $0 < milestoneGrace }
    }

    /// Special occasions take the place of the morning greeting: a "together"
    /// milestone, then a new season. Call where a morning greeting would be shown.
    public static func occasion(at now: Date, daysTogether: Int, season: Season,
                                memory: GreetingMemory) -> (Greeting?, GreetingMemory) {
        var memory = memory
        if let mark = milestone(forDay: daysTogether), memory.milestone < mark {
            memory.milestone = mark
            noteSeason(season, in: &memory)
            return (.together(days: mark), memory)
        }
        if let seen = memory.season, seen != season.rawValue {
            memory.season = season.rawValue
            return (.newSeason(season), memory)
        }
        noteSeason(season, in: &memory)
        return (nil, memory)
    }

    private static func noteSeason(_ season: Season, in memory: inout GreetingMemory) {
        memory.season = season.rawValue
    }

    /// It just started snowing: the winter's first snow gets a hello. Winters
    /// are keyed by the year two months earlier, so December–February is one.
    public static func snowStarted(at now: Date, memory: GreetingMemory, calendar: Calendar) -> (Greeting?, GreetingMemory) {
        var memory = memory
        let winterStart = calendar.date(byAdding: .month, value: -2, to: now) ?? now
        let key = "winter-\(calendar.component(.year, from: winterStart))"
        guard memory.firstSnowWinter != key else { return (nil, memory) }
        memory.firstSnowWinter = key
        return (.firstSnow, memory)
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
