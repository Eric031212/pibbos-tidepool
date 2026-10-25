import Foundation

/// dawn / day / dusk / night (CLAUDE.md Section 10).
public enum TimeOfDay: String, Sendable, CaseIterable {
    case dawn, day, dusk, night
}

public enum Season: String, Sendable, CaseIterable {
    case spring, summer, autumn, winter

    /// Meteorological seasons, flipped for the southern hemisphere.
    public static func of(month: Int, latitude: Double) -> Season {
        let northern: Season
        switch month {
        case 3...5: northern = .spring
        case 6...8: northern = .summer
        case 9...11: northern = .autumn
        default: northern = .winter
        }
        guard latitude < 0 else { return northern }
        switch northern {
        case .spring: return .autumn
        case .summer: return .winter
        case .autumn: return .spring
        case .winter: return .summer
        }
    }
}

public enum Weather: String, Sendable, CaseIterable {
    case clear, cloudy, rain, snow, storm

    /// Maps a MET Norway `symbol_code` (spike 5). Returns nil for unknown
    /// symbols so callers keep the previous value.
    public static func fromMETSymbol(_ symbol: String) -> Weather? {
        let base = symbol.split(separator: "_").first.map(String.init) ?? symbol
        if base.contains("thunder") { return .storm }
        if base.contains("snow") { return .snow }
        if base.contains("rain") || base.contains("sleet") { return .rain }
        switch base {
        case "clearsky", "fair": return .clear
        case "partlycloudy", "cloudy", "fog": return .cloudy
        default: return nil
        }
    }
}

public struct Coordinate: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// ~1 km precision: what we send to the weather service (privacy).
    public var rounded: Coordinate {
        Coordinate(latitude: (latitude * 100).rounded() / 100, longitude: (longitude * 100).rounded() / 100)
    }
}

/// Everything Pibbo's small actions depend on.
public struct WorldContext: Equatable, Sendable {
    public var timeOfDay: TimeOfDay
    public var season: Season
    /// nil until the first successful weather fetch, or when offline.
    public var weather: Weather?
    /// The holiday Pibbo dresses up for today, if any.
    public var holiday: Holiday?
    /// How full the moon is, in eighths (0 = new, 1 = full): moonlight on the
    /// night water.
    public var moonlight: Double

    public init(timeOfDay: TimeOfDay, season: Season, weather: Weather?, holiday: Holiday? = nil, moonlight: Double = 1) {
        self.timeOfDay = timeOfDay
        self.season = season
        self.weather = weather
        self.holiday = holiday
        self.moonlight = moonlight
    }

    /// A clear night: shooting stars can happen.
    public var isClearNight: Bool { timeOfDay == .night && weather == .clear }
}
