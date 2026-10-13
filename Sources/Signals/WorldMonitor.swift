import Foundation
import World

/// Time of day, season and weather for Pibbo's small actions (spike 5).
///
/// - Location: ipwho.is when its time zone matches the system's, otherwise
///   the bundled zone.tab city of the system time zone. Never CoreLocation.
/// - Weather: MET Norway every 1–3 hours, never before `Expires`, with an
///   identifying User-Agent and coordinates rounded to ~1 km.
/// - Time of day and season: computed locally; one timer for the next change.
/// No polling: three low-frequency timers, all with tolerance.
final class WorldMonitor {
    var onChange: ((WorldContext) -> Void)?
    private(set) var context: WorldContext

    static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        return "PibbosTidepool/\(version) (+https://github.com/Eric031212/pibbos-tidepool)"
    }()
    private static let coordinateKey = "lastCoordinate"

    private var coordinate: Coordinate
    private let zoneCoordinate: Coordinate?
    private let session: URLSession
    private var timeTimer: Timer?
    private var weatherTimer: Timer?
    private var lastModified: String?

    init(zoneTab: URL?) {
        let table = zoneTab.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        zoneCoordinate = ZoneTab.coordinate(for: TimeZone.current.identifier, in: table)
        if let saved = UserDefaults.standard.array(forKey: Self.coordinateKey) as? [Double], saved.count == 2 {
            coordinate = Coordinate(latitude: saved[0], longitude: saved[1])
        } else {
            coordinate = zoneCoordinate ?? Coordinate(latitude: 0, longitude: 0)
        }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
        session = URLSession(configuration: config)
        context = Self.makeContext(coordinate: coordinate, weather: nil)
    }

    func start() {
        scheduleTimeOfDay()
        locate { [weak self] in self?.refreshWeather() }
    }

    // MARK: - Location

    private func locate(then next: @escaping () -> Void) {
        let request = URLRequest(url: URL(string: "https://ipwho.is/")!)
        session.dataTask(with: request) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if let data,
                   let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                   json["success"] as? Bool == true,
                   let lat = json["latitude"] as? Double, let lon = json["longitude"] as? Double,
                   (json["timezone"] as? [String: Any])?["id"] as? String == TimeZone.current.identifier {
                    self.coordinate = Coordinate(latitude: lat, longitude: lon).rounded
                } else if let zone = self.zoneCoordinate {
                    // Offline, or the IP is elsewhere (VPN): trust the time zone.
                    self.coordinate = zone.rounded
                }
                UserDefaults.standard.set([self.coordinate.latitude, self.coordinate.longitude], forKey: Self.coordinateKey)
                self.publish(weather: self.context.weather)
                self.scheduleTimeOfDay()
                next()
            }
        }.resume()
    }

    // MARK: - Weather

    private func refreshWeather() {
        let c = coordinate.rounded
        var request = URLRequest(url: URL(string: "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=\(c.latitude)&lon=\(c.longitude)")!)
        if let lastModified { request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }
        session.dataTask(with: request) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let http = response as? HTTPURLResponse
                var expires: Date?
                if let http, http.statusCode == 200 || http.statusCode == 304 {
                    expires = http.value(forHTTPHeaderField: "Expires").flatMap(Self.httpDate.date(from:))
                    if http.statusCode == 200, let data {
                        self.lastModified = http.value(forHTTPHeaderField: "Last-Modified")
                        if let symbol = Self.currentSymbol(in: data), let weather = Weather.fromMETSymbol(symbol) {
                            self.publish(weather: weather)
                        }
                    }
                    self.scheduleWeather(after: expires, failed: false)
                } else {
                    self.scheduleWeather(after: nil, failed: true)
                }
            }
        }.resume()
    }

    private static func currentSymbol(in data: Data) -> String? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let properties = json["properties"] as? [String: Any],
              let series = properties["timeseries"] as? [[String: Any]],
              let first = series.first?["data"] as? [String: Any],
              let next = first["next_1_hours"] as? [String: Any],
              let summary = next["summary"] as? [String: Any] else { return nil }
        return summary["symbol_code"] as? String
    }

    /// Next fetch: after `Expires` but at least an hour and at most three
    /// from now, with random jitter so clients don't all hit MET at once.
    private func scheduleWeather(after expires: Date?, failed: Bool) {
        let now = Date()
        var next = failed ? now.addingTimeInterval(30 * 60) : max(expires ?? now, now.addingTimeInterval(3600))
        next = min(next, now.addingTimeInterval(3 * 3600)).addingTimeInterval(.random(in: 0...600))
        weatherTimer?.invalidate()
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in self?.refreshWeather() }
        timer.tolerance = 120
        RunLoop.main.add(timer, forMode: .common)
        weatherTimer = timer
    }

    private static let httpDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    // MARK: - Time of day and season

    private func scheduleTimeOfDay() {
        timeTimer?.invalidate()
        let next = SunClock.nextChange(after: Date(), coordinate: coordinate).addingTimeInterval(30)
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.publish(weather: self.context.weather)
            self.scheduleTimeOfDay()
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        timeTimer = timer
    }

    private func publish(weather: Weather?) {
        let updated = Self.makeContext(coordinate: coordinate, weather: weather)
        guard updated != context else { return }
        context = updated
        onChange?(updated)
    }

    private static func makeContext(coordinate: Coordinate, weather: Weather?) -> WorldContext {
        let now = Date()
        let month = Calendar.current.component(.month, from: now)
        return WorldContext(timeOfDay: SunClock.timeOfDay(at: now, coordinate: coordinate),
                            season: Season.of(month: month, latitude: coordinate.latitude),
                            weather: weather)
    }
}
