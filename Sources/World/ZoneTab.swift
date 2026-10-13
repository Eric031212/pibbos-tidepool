import Foundation

/// Fallback location: the main city of the system time zone, from a bundled
/// tzdb `zone.tab` (public domain). Used offline or when the IP lookup's time
/// zone disagrees with the system's (e.g. a VPN).
public enum ZoneTab {
    public static func coordinate(for identifier: String, in table: String) -> Coordinate? {
        for line in table.split(separator: "\n") where !line.hasPrefix("#") {
            let columns = line.split(separator: "\t")
            if columns.count >= 3, columns[2] == identifier {
                return parse(String(columns[1]))
            }
        }
        return nil
    }

    /// Parses "+404251-0740023" (±DDMM[SS]±DDDMM[SS]).
    static func parse(_ text: String) -> Coordinate? {
        guard let split = text.dropFirst().firstIndex(where: { $0 == "+" || $0 == "-" }) else { return nil }
        func degrees(_ part: Substring, degreeDigits: Int) -> Double? {
            let sign: Double = part.first == "-" ? -1 : 1
            let digits = Array(part.dropFirst())
            guard digits.count >= degreeDigits + 2,
                  let d = Double(String(digits[0..<degreeDigits])),
                  let m = Double(String(digits[degreeDigits..<degreeDigits + 2])) else { return nil }
            let s = digits.count >= degreeDigits + 4 ? Double(String(digits[(degreeDigits + 2)..<(degreeDigits + 4)])) ?? 0 : 0
            return sign * (d + m / 60 + s / 3600)
        }
        guard let lat = degrees(text[..<split], degreeDigits: 2),
              let lon = degrees(text[split...], degreeDigits: 3) else { return nil }
        return Coordinate(latitude: lat, longitude: lon)
    }
}
