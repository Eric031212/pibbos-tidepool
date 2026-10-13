import XCTest
@testable import World

final class WorldTests: XCTestCase {
    let tokyo = Coordinate(latitude: 35.68, longitude: 139.69)

    func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    func testSeasonsFlipInTheSouth() {
        XCTAssertEqual(Season.of(month: 1, latitude: 40), .winter)
        XCTAssertEqual(Season.of(month: 4, latitude: 40), .spring)
        XCTAssertEqual(Season.of(month: 7, latitude: 40), .summer)
        XCTAssertEqual(Season.of(month: 10, latitude: 40), .autumn)
        XCTAssertEqual(Season.of(month: 1, latitude: -33), .summer)
        XCTAssertEqual(Season.of(month: 10, latitude: -33), .spring)
    }

    func testMETSymbols() {
        XCTAssertEqual(Weather.fromMETSymbol("clearsky_day"), .clear)
        XCTAssertEqual(Weather.fromMETSymbol("fair_night"), .clear)
        XCTAssertEqual(Weather.fromMETSymbol("partlycloudy_polartwilight"), .cloudy)
        XCTAssertEqual(Weather.fromMETSymbol("fog"), .cloudy)
        XCTAssertEqual(Weather.fromMETSymbol("lightrainshowers_day"), .rain)
        XCTAssertEqual(Weather.fromMETSymbol("heavysleet"), .rain)
        XCTAssertEqual(Weather.fromMETSymbol("snowshowers_night"), .snow)
        XCTAssertEqual(Weather.fromMETSymbol("rainandthunder"), .storm)
        XCTAssertEqual(Weather.fromMETSymbol("heavysnowshowersandthunder_day"), .storm)
        XCTAssertNil(Weather.fromMETSymbol("somethingnew"))
    }

    func testTimeOfDayAroundSunriseAndSunset() throws {
        let noon = date("2026-10-12T03:00:00Z")  // 12:00 in Tokyo
        let day = try XCTUnwrap(SunClock.day(containing: noon, at: tokyo))
        // Tokyo in mid-October: sunrise ~05:40, sunset ~17:10 local (UTC+9).
        let hour = { (d: Date) -> Double in (d.timeIntervalSince1970 / 3600 + 9).truncatingRemainder(dividingBy: 24) }
        XCTAssertEqual(hour(day.sunrise), 5.7, accuracy: 0.3)
        XCTAssertEqual(hour(day.sunset), 17.2, accuracy: 0.3)
        XCTAssertLessThan(day.dawn, day.sunrise)
        XCTAssertLessThan(day.sunset, day.dusk)

        XCTAssertEqual(SunClock.timeOfDay(at: day.sunrise.addingTimeInterval(-600), coordinate: tokyo), .dawn)
        XCTAssertEqual(SunClock.timeOfDay(at: noon, coordinate: tokyo), .day)
        XCTAssertEqual(SunClock.timeOfDay(at: day.sunset.addingTimeInterval(-600), coordinate: tokyo), .dusk)
        XCTAssertEqual(SunClock.timeOfDay(at: day.dusk.addingTimeInterval(7200), coordinate: tokyo), .night)
    }

    func testTimeOfDayIsRightAllAroundTheClockFarFromUTC() {
        // Walk a whole day in 10-minute steps in Tokyo, Honolulu and Auckland:
        // every moment must fall in exactly the expected order with no gaps.
        for place in [tokyo, Coordinate(latitude: 21.31, longitude: -157.86), Coordinate(latitude: -36.85, longitude: 174.76)] {
            var seen: [TimeOfDay] = []
            var t = date("2026-10-12T00:00:00Z")
            for _ in 0..<(6 * 24) {
                let phase = SunClock.timeOfDay(at: t, coordinate: place)
                if seen.last != phase { seen.append(phase) }
                t = t.addingTimeInterval(600)
            }
            let cycle: [TimeOfDay] = [.dawn, .day, .dusk, .night]
            for (a, b) in zip(seen, seen.dropFirst()) {
                XCTAssertEqual(cycle[(cycle.firstIndex(of: a)! + 1) % 4], b, "\(place): \(seen)")
            }
            XCTAssertTrue(seen.contains(.dawn) && seen.contains(.day) && seen.contains(.dusk) && seen.contains(.night), "\(place): \(seen)")
        }
    }

    func testNextChangeIsTheNextBoundary() throws {
        let noon = date("2026-10-12T03:00:00Z")
        let day = try XCTUnwrap(SunClock.day(containing: noon, at: tokyo))
        let next = SunClock.nextChange(after: noon, coordinate: tokyo)
        // Day ends half an hour before sunset.
        XCTAssertEqual(next.timeIntervalSince(day.sunset.addingTimeInterval(-1800)), 0, accuracy: 1)
        XCTAssertEqual(SunClock.timeOfDay(at: next.addingTimeInterval(60), coordinate: tokyo), .dusk)
    }

    func testPolarDayAndNight() {
        let tromsoNorth = Coordinate(latitude: 78.2, longitude: 15.6)  // Svalbard
        XCTAssertEqual(SunClock.timeOfDay(at: date("2026-06-21T00:00:00Z"), coordinate: tromsoNorth), .day)
        XCTAssertEqual(SunClock.timeOfDay(at: date("2026-12-21T12:00:00Z"), coordinate: tromsoNorth), .night)
    }

    func testZoneTab() {
        let table = "# comment\nJP\t+353916+1394441\tAsia/Tokyo\nAU\t-3352+15113\tAustralia/Sydney\tNSW\n"
        let tokyo = ZoneTab.coordinate(for: "Asia/Tokyo", in: table)!
        XCTAssertEqual(tokyo.latitude, 35.654, accuracy: 0.001)
        XCTAssertEqual(tokyo.longitude, 139.745, accuracy: 0.001)
        let sydney = ZoneTab.coordinate(for: "Australia/Sydney", in: table)!
        XCTAssertEqual(sydney.latitude, -33.867, accuracy: 0.001)
        XCTAssertNil(ZoneTab.coordinate(for: "Mars/Olympus", in: table))
    }

    func testRoundingForPrivacy() {
        XCTAssertEqual(Coordinate(latitude: 35.68123, longitude: 139.76712).rounded,
                       Coordinate(latitude: 35.68, longitude: 139.77))
    }

    func testActionRules() {
        let sunnySummer = ActionRules.actions(for: WorldContext(timeOfDay: .day, season: .summer, weather: .clear))
        XCTAssertTrue(sunnySummer.contains("sunbathe"))
        XCTAssertTrue(sunnySummer.contains("water"))

        let rainy = ActionRules.actions(for: WorldContext(timeOfDay: .day, season: .autumn, weather: .rain))
        XCTAssertTrue(rainy.contains("raindrops"))
        XCTAssertFalse(rainy.contains("water"), "no watering in the rain")

        let storm = ActionRules.actions(for: WorldContext(timeOfDay: .day, season: .summer, weather: .storm))
        XCTAssertEqual(Set(storm), ["huddle", "groom"])

        let clearNight = ActionRules.actions(for: WorldContext(timeOfDay: .night, season: .winter, weather: .clear))
        XCTAssertTrue(clearNight.contains("stargaze"))
        XCTAssertTrue(clearNight.contains("cocoa"))
        XCTAssertFalse(clearNight.contains("sunbathe"))

        let unknownWeather = ActionRules.actions(for: WorldContext(timeOfDay: .dawn, season: .spring, weather: nil))
        XCTAssertTrue(unknownWeather.contains("stretch"))
        XCTAssertTrue(unknownWeather.contains("petal"))
    }

    func testGardenGrowsAndStops() {
        XCTAssertEqual(Garden.stage(daysSinceFirstLaunch: 0, stageCount: 6), 0)
        XCTAssertEqual(Garden.stage(daysSinceFirstLaunch: 1.5, stageCount: 6), 1)
        XCTAssertEqual(Garden.stage(daysSinceFirstLaunch: 7, stageCount: 6), 3)
        XCTAssertEqual(Garden.stage(daysSinceFirstLaunch: 400, stageCount: 6), 5)
        XCTAssertEqual(Garden.stage(daysSinceFirstLaunch: 400, stageCount: 3), 2, "skins with fewer stages")
        XCTAssertEqual(Garden.stage(daysSinceFirstLaunch: -3, stageCount: 6), 0, "clock set backwards")
    }
}
