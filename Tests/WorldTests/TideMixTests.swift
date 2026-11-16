import XCTest
@testable import World

final class TideMixTests: XCTestCase {
    private func mix(_ time: TimeOfDay, _ season: Season, _ weather: Weather?) -> [String: Float] {
        TideMix.layers(for: WorldContext(timeOfDay: time, season: season, weather: weather))
    }

    func testTheSoundFollowsTheWeatherAndTime() {
        XCTAssertEqual(mix(.day, .spring, .clear), ["waves": 1])
        XCTAssertEqual(mix(.dusk, .autumn, nil), ["waves": 1], "unknown weather: just the waves")
        XCTAssertEqual(mix(.night, .autumn, .clear), ["nightwaves": 1])
        XCTAssertEqual(mix(.night, .summer, .cloudy), ["nightwaves": 1, "crickets": 0.6], "summer nights have crickets")
        XCTAssertEqual(mix(.day, .summer, .rain), ["rain": 1, "waves": 0.25])
        XCTAssertEqual(mix(.night, .winter, .storm), ["rain": 1, "nightwaves": 0.25])
        XCTAssertEqual(mix(.day, .winter, .snow), ["wind": 0.8, "waves": 0.2])
    }

    func testEveryLoopIsBundled() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var names = Set<String>()
        for time in TimeOfDay.allCases { for season in Season.allCases { for weather in Weather.allCases + [nil] {
            names.formUnion(mix(time, season, weather).keys)
        } } }
        for name in names {
            XCTAssertTrue(FileManager.default.fileExists(atPath: repo.appendingPathComponent("Assets/Sounds/\(name).caf").path), name)
        }
    }
}
