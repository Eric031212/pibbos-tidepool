import Foundation

/// Local sunrise/sunset and time of day from a coordinate, no network
/// (spike 5: matches Open-Meteo within a minute). Sunrise equation, NOAA
/// simplified; civil twilight at −6°.
public enum SunClock {
    public struct Day: Equatable, Sendable {
        public let dawn: Date
        public let sunrise: Date
        public let sunset: Date
        public let dusk: Date
    }

    /// nil during polar day or night.
    public static func day(containing date: Date, at coordinate: Coordinate) -> Day? {
        guard let sun = event(on: date, at: coordinate, altitude: -0.833),
              let civil = event(on: date, at: coordinate, altitude: -6) else { return nil }
        return Day(dawn: civil.rise, sunrise: sun.rise, sunset: sun.set, dusk: civil.set)
    }

    /// Dawn runs from civil dawn to half an hour after sunrise; dusk from half
    /// an hour before sunset to civil dusk.
    public static func timeOfDay(at date: Date, coordinate: Coordinate) -> TimeOfDay {
        // The sunrise equation picks its solar day from the UTC date, which
        // can be a day off from the local date far from Greenwich, so check
        // the neighbouring days' windows too.
        let days = [-86_400.0, 0, 86_400].compactMap { day(containing: date.addingTimeInterval($0), at: coordinate) }
        guard !days.isEmpty else { return polarFallback(date: date, coordinate: coordinate) }
        let halfHour: TimeInterval = 30 * 60
        for day in days {
            switch date {
            case day.dawn..<day.sunrise.addingTimeInterval(halfHour): return .dawn
            case day.sunrise.addingTimeInterval(halfHour)..<day.sunset.addingTimeInterval(-halfHour): return .day
            case day.sunset.addingTimeInterval(-halfHour)..<day.dusk: return .dusk
            default: continue
            }
        }
        return .night
    }

    /// The next moment the time of day may change (for a single timer).
    public static func nextChange(after date: Date, coordinate: Coordinate) -> Date {
        let halfHour: TimeInterval = 30 * 60
        var candidates: [Date] = []
        for offset in [-86_400.0, 0, 86_400] {
            if let day = day(containing: date.addingTimeInterval(offset), at: coordinate) {
                candidates += [day.dawn, day.sunrise.addingTimeInterval(halfHour),
                               day.sunset.addingTimeInterval(-halfHour), day.dusk]
            }
        }
        return candidates.filter { $0 > date.addingTimeInterval(1) }.min() ?? date.addingTimeInterval(6 * 3600)
    }

    private static func polarFallback(date: Date, coordinate: Coordinate) -> TimeOfDay {
        // Polar day in local summer, polar night in winter.
        let month = Calendar(identifier: .gregorian).component(.month, from: date)
        let northernSummer = (4...9).contains(month)
        return (coordinate.latitude >= 0) == northernSummer ? .day : .night
    }

    private static func event(on date: Date, at c: Coordinate, altitude: Double) -> (rise: Date, set: Date)? {
        let rad = Double.pi / 180
        let julianDay = date.timeIntervalSince1970 / 86400 + 2440587.5
        let n = (julianDay - 2451545.0 + 0.0008).rounded()
        let meanSolarNoon = n - c.longitude / 360
        let m = (357.5291 + 0.98560028 * meanSolarNoon).truncatingRemainder(dividingBy: 360)
        let center = 1.9148 * sin(m * rad) + 0.02 * sin(2 * m * rad) + 0.0003 * sin(3 * m * rad)
        let lambda = (m + center + 180 + 102.9372).truncatingRemainder(dividingBy: 360)
        let transit = 2451545.0 + meanSolarNoon + 0.0053 * sin(m * rad) - 0.0069 * sin(2 * lambda * rad)
        let declination = asin(sin(lambda * rad) * sin(23.4397 * rad))
        let cosHourAngle = (sin(altitude * rad) - sin(c.latitude * rad) * sin(declination))
            / (cos(c.latitude * rad) * cos(declination))
        guard abs(cosHourAngle) <= 1 else { return nil }
        let hourAngle = acos(cosHourAngle) / rad
        func toDate(_ jd: Double) -> Date { Date(timeIntervalSince1970: (jd - 2440587.5) * 86400) }
        return (toDate(transit - hourAngle / 360), toDate(transit + hourAngle / 360))
    }
}
