// Spike 5: location and weather.
// Compares ways to get an approximate location without CoreLocation, fetches
// current weather from Open-Meteo and MET Norway, maps both to Tidepool's five
// weather categories, and derives season and time of day locally.
// Never prints the IP address. Coordinates sent to weather services are
// rounded to 2 decimals (~1 km).

import Foundation

setvbuf(stdout, nil, _IOLBF, 0)

func section(_ title: String) { print("\n== \(title)") }

struct Coordinate {
    let latitude: Double
    let longitude: Double
    var rounded: Coordinate { Coordinate(latitude: (latitude * 100).rounded() / 100, longitude: (longitude * 100).rounded() / 100) }
    var text: String { String(format: "%.2f, %.2f", latitude, longitude) }
}

enum Weather: String { case clear, cloudy, rain, snow, storm, unknown }

let session: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 10
    return URLSession(configuration: config)
}()

/// GET with timing; returns (body, HTTP response) or prints the failure.
func get(_ url: String, headers: [String: String] = [:]) async -> (Data, HTTPURLResponse)? {
    var request = URLRequest(url: URL(string: url)!)
    headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
    let start = Date()
    do {
        let (data, response) = try await session.data(for: request)
        let http = response as! HTTPURLResponse
        print(String(format: "  HTTP %d, %d bytes, %.0f ms", http.statusCode, data.count, Date().timeIntervalSince(start) * 1000))
        return (data, http)
    } catch {
        print(String(format: "  FAILED after %.0f ms: %@", Date().timeIntervalSince(start) * 1000, error.localizedDescription))
        return nil
    }
}

// MARK: - 1. Time zone (offline)

/// Parses a tzdb zone.tab coordinate such as "+404251-0740023" (±DDMM[SS]±DDDMM[SS]).
func parseZoneTabCoordinate(_ text: String) -> Coordinate? {
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
    guard let lat = degrees(text[..<split], degreeDigits: 2), let lon = degrees(text[split...], degreeDigits: 3) else { return nil }
    return Coordinate(latitude: lat, longitude: lon)
}

func zoneTabCoordinate(for identifier: String) -> Coordinate? {
    guard let table = try? String(contentsOfFile: "/usr/share/zoneinfo/zone.tab", encoding: .utf8) else { return nil }
    for line in table.split(separator: "\n") where !line.hasPrefix("#") {
        let columns = line.split(separator: "\t")
        if columns.count >= 3, columns[2] == identifier { return parseZoneTabCoordinate(String(columns[1])) }
    }
    return nil
}

section("1. System time zone (offline, no permission)")
let systemZone = TimeZone.current
print("  TimeZone.current = \(systemZone.identifier), UTC\(systemZone.secondsFromGMT() >= 0 ? "+" : "")\(Double(systemZone.secondsFromGMT()) / 3600)")
print("  Locale.current.region = \(Locale.current.region?.identifier ?? "nil")")
let zoneCoordinate = zoneTabCoordinate(for: systemZone.identifier)
print("  zone.tab coordinate of the zone's main city = \(zoneCoordinate?.text ?? "not found")")

// MARK: - 2. IP lookup

struct IPWhoResponse: Decodable {
    struct Zone: Decodable { let id: String? }
    let success: Bool
    let message: String?
    let city: String?
    let region: String?
    let country_code: String?
    let latitude: Double?
    let longitude: Double?
    let timezone: Zone?
}

section("2. IP lookup: https://ipwho.is/ (free tier, no key)")
var ipCoordinate: Coordinate?
var ipZone: String?
if let (data, _) = await get("https://ipwho.is/") {
    if let keys = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
        print("  top-level keys: \(keys.keys.sorted())")
    }
    if let result = try? JSONDecoder().decode(IPWhoResponse.self, from: data), result.success,
       let lat = result.latitude, let lon = result.longitude {
        ipCoordinate = Coordinate(latitude: lat, longitude: lon)
        ipZone = result.timezone?.id
        print("  city=\(result.city ?? "?"), region=\(result.region ?? "?"), country=\(result.country_code ?? "?"), coordinate=\(ipCoordinate!.text), timezone=\(ipZone ?? "?")")
    } else {
        print("  could not decode: \(String(data: data, encoding: .utf8)?.prefix(200) ?? "")")
    }
}

// MARK: - Choose the coordinate

section("3. Coordinate used for weather")
let chosen: Coordinate?
if let ip = ipCoordinate, ipZone == systemZone.identifier {
    chosen = ip.rounded
    print("  IP time zone matches the system time zone -> use IP coordinate \(chosen!.text)")
} else if let zone = zoneCoordinate {
    chosen = zone.rounded
    print("  \(ipCoordinate == nil ? "IP lookup failed" : "IP time zone \(ipZone ?? "?") != system \(systemZone.identifier) (VPN?)") -> use zone coordinate \(chosen!.text)")
} else {
    chosen = nil
    print("  no coordinate available")
}
if let ip = ipCoordinate, let zone = zoneCoordinate {
    let km = 111.0 * hypot(ip.latitude - zone.latitude, (ip.longitude - zone.longitude) * cos(ip.latitude * .pi / 180))
    print(String(format: "  distance between IP coordinate and zone city: ~%.0f km", km))
}

// MARK: - 4. Weather

func categoryForWMO(_ code: Int) -> Weather {
    switch code {
    case 0, 1: return .clear
    case 2, 3, 45, 48: return .cloudy
    case 51...67, 80...82: return .rain
    case 71...77, 85, 86: return .snow
    case 95...99: return .storm
    default: return .unknown
    }
}

func categoryForMETSymbol(_ symbol: String) -> Weather {
    let base = symbol.split(separator: "_").first.map(String.init) ?? symbol  // drop _day/_night/_polartwilight
    if base.contains("thunder") { return .storm }
    if base.contains("snow") { return .snow }
    if base.contains("rain") || base.contains("sleet") { return .rain }
    switch base {
    case "clearsky", "fair": return .clear
    case "partlycloudy", "cloudy", "fog": return .cloudy
    default: return .unknown
    }
}

struct OpenMeteoResponse: Decodable {
    struct Current: Decodable { let weather_code: Int; let temperature_2m: Double; let is_day: Int }
    struct Daily: Decodable { let sunrise: [Int]; let sunset: [Int] }
    let current: Current
    let daily: Daily
}

struct METResponse: Decodable {
    struct Properties: Decodable { let timeseries: [Step] }
    struct Step: Decodable { let time: String; let data: StepData }
    struct StepData: Decodable { let instant: Instant; let next_1_hours: Next? }
    struct Instant: Decodable { let details: [String: Double] }
    struct Next: Decodable { let summary: Summary }
    struct Summary: Decodable { let symbol_code: String }
    let properties: Properties
}

var openMeteoSun: (sunrise: Date, sunset: Date)?

if let c = chosen {
    section("4a. Open-Meteo (free tier = non-commercial only)")
    let url = "https://api.open-meteo.com/v1/forecast?latitude=\(c.latitude)&longitude=\(c.longitude)&current=weather_code,temperature_2m,is_day&daily=sunrise,sunset&timezone=GMT&timeformat=unixtime&forecast_days=1"
    if let (data, _) = await get(url), let result = try? JSONDecoder().decode(OpenMeteoResponse.self, from: data) {
        let code = result.current.weather_code
        print("  weather_code=\(code) -> \(categoryForWMO(code).rawValue), temperature=\(result.current.temperature_2m)°C, is_day=\(result.current.is_day)")
        if let rise = result.daily.sunrise.first, let set = result.daily.sunset.first {
            openMeteoSun = (Date(timeIntervalSince1970: TimeInterval(rise)), Date(timeIntervalSince1970: TimeInterval(set)))
        }
    }

    section("4b. MET Norway locationforecast/2.0/compact (free, CC BY 4.0, commercial OK)")
    let metURL = "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=\(c.latitude)&lon=\(c.longitude)"
    if let (data, http) = await get(metURL, headers: ["User-Agent": "TidepoolSpike/0.1 (prototype, macOS)"]) {
        print("  Expires: \(http.value(forHTTPHeaderField: "Expires") ?? "-")  Last-Modified: \(http.value(forHTTPHeaderField: "Last-Modified") ?? "-")")
        if let result = try? JSONDecoder().decode(METResponse.self, from: data), let first = result.properties.timeseries.first {
            let symbol = first.data.next_1_hours?.summary.symbol_code ?? "?"
            print("  first step \(first.time): symbol_code=\(symbol) -> \(categoryForMETSymbol(symbol).rawValue), air_temperature=\(first.data.instant.details["air_temperature"].map { "\($0)" } ?? "?")°C")
        } else {
            print("  could not decode")
        }
    }
}

// MARK: - 5. Season and time of day (offline)

/// Sunrise equation (Wikipedia / NOAA simplified). altitude: -0.833° for
/// sunrise/sunset, -6° for civil dawn/dusk. Returns nil during polar day/night.
func sunEvent(on date: Date, at c: Coordinate, altitude: Double) -> (rise: Date, set: Date)? {
    let rad = Double.pi / 180
    let julianDay = date.timeIntervalSince1970 / 86400 + 2440587.5
    let n = (julianDay - 2451545.0 + 0.0008).rounded()
    let meanSolarNoon = n - c.longitude / 360
    let m = (357.5291 + 0.98560028 * meanSolarNoon).truncatingRemainder(dividingBy: 360)
    let center = 1.9148 * sin(m * rad) + 0.02 * sin(2 * m * rad) + 0.0003 * sin(3 * m * rad)
    let lambda = (m + center + 180 + 102.9372).truncatingRemainder(dividingBy: 360)
    let transit = 2451545.0 + meanSolarNoon + 0.0053 * sin(m * rad) - 0.0069 * sin(2 * lambda * rad)
    let declination = asin(sin(lambda * rad) * sin(23.4397 * rad))
    let cosHourAngle = (sin(altitude * rad) - sin(c.latitude * rad) * sin(declination)) / (cos(c.latitude * rad) * cos(declination))
    guard abs(cosHourAngle) <= 1 else { return nil }
    let hourAngle = acos(cosHourAngle) / rad
    func toDate(_ jd: Double) -> Date { Date(timeIntervalSince1970: (jd - 2440587.5) * 86400) }
    return (toDate(transit - hourAngle / 360), toDate(transit + hourAngle / 360))
}

section("5. Season and time of day (computed locally)")
let now = Date()
let clock = DateFormatter()
clock.timeZone = systemZone
clock.dateFormat = "HH:mm"
if let c = chosen ?? zoneCoordinate {
    let month = Calendar.current.component(.month, from: now)
    let northernSeason = ["winter", "winter", "spring", "spring", "spring", "summer", "summer", "summer", "autumn", "autumn", "autumn", "winter"][month - 1]
    let southern = ["winter": "summer", "summer": "winter", "spring": "autumn", "autumn": "spring"]
    let season = c.latitude < 0 ? southern[northernSeason]! : northernSeason
    print("  hemisphere=\(c.latitude < 0 ? "south" : "north"), month=\(month) -> season=\(season)")

    if let sun = sunEvent(on: now, at: c, altitude: -0.833), let civil = sunEvent(on: now, at: c, altitude: -6) {
        print("  local calc: dawn \(clock.string(from: civil.rise))  sunrise \(clock.string(from: sun.rise))  sunset \(clock.string(from: sun.set))  dusk \(clock.string(from: civil.set))")
        if let api = openMeteoSun {
            print(String(format: "  Open-Meteo:            sunrise %@  sunset %@   (diff %+.1f / %+.1f min)",
                         clock.string(from: api.sunrise), clock.string(from: api.sunset),
                         sun.rise.timeIntervalSince(api.sunrise) / 60, sun.set.timeIntervalSince(api.sunset) / 60))
        }
        let halfHour: TimeInterval = 30 * 60
        let phase: String
        switch now {
        case civil.rise..<sun.rise.addingTimeInterval(halfHour): phase = "dawn"
        case sun.rise.addingTimeInterval(halfHour)..<sun.set.addingTimeInterval(-halfHour): phase = "day"
        case sun.set.addingTimeInterval(-halfHour)..<civil.set: phase = "dusk"
        default: phase = "night"
        }
        print("  now \(clock.string(from: now)) -> time of day = \(phase)")
    } else {
        print("  polar day or night: no sunrise/sunset today")
    }
}
print("")
