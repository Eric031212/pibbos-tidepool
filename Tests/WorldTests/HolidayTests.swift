import XCTest
@testable import World

final class HolidayTests: XCTestCase {
    let utc = TimeZone(identifier: "UTC")!

    func day(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso + "T12:00:00Z")! }

    func testWesternHolidaysForEveryone() {
        XCTAssertEqual(Holidays.current(on: day("2026-10-31"), region: "US", timeZone: utc), .halloween)
        XCTAssertEqual(Holidays.current(on: day("2026-10-25"), region: "DE", timeZone: utc), .halloween)
        XCTAssertNil(Holidays.current(on: day("2026-10-24"), region: "US", timeZone: utc))
        XCTAssertNil(Holidays.current(on: day("2026-11-01"), region: "US", timeZone: utc))
        XCTAssertEqual(Holidays.current(on: day("2026-12-24"), region: "CN", timeZone: utc), .christmas)
        XCTAssertNil(Holidays.current(on: day("2026-12-27"), region: "US", timeZone: utc))
        XCTAssertEqual(Holidays.current(on: day("2026-12-31"), region: "JP", timeZone: utc), .newYear)
        XCTAssertEqual(Holidays.current(on: day("2027-01-02"), region: nil, timeZone: utc), .newYear)
        XCTAssertNil(Holidays.current(on: day("2027-01-03"), region: nil, timeZone: utc))
    }

    func testLunarNewYearOnlyWhereItIsCelebrated() {
        // Lunar New Year 2027 falls on February 6; its eve is February 5.
        XCTAssertEqual(Holidays.current(on: day("2027-02-05"), region: "CN", timeZone: utc), .lunarNewYear)
        XCTAssertEqual(Holidays.current(on: day("2027-02-06"), region: "TW", timeZone: utc), .lunarNewYear)
        XCTAssertEqual(Holidays.current(on: day("2027-02-11"), region: "KR", timeZone: utc), .lunarNewYear, "6th day")
        XCTAssertNil(Holidays.current(on: day("2027-02-12"), region: "CN", timeZone: utc), "7th day: over")
        XCTAssertNil(Holidays.current(on: day("2027-02-04"), region: "CN", timeZone: utc))
        XCTAssertNil(Holidays.current(on: day("2027-02-06"), region: "US", timeZone: utc), "not a US holiday here")
    }

    func testLunarNewYearMovesEveryYear() {
        // 2026: February 17.
        XCTAssertEqual(Holidays.current(on: day("2026-02-17"), region: "CN", timeZone: utc), .lunarNewYear)
        XCTAssertNil(Holidays.current(on: day("2026-02-06"), region: "CN", timeZone: utc))
    }

    func testLocalDateDecides() {
        // 23:30 on Oct 24 in New York is already Oct 25 in UTC.
        let late = ISO8601DateFormatter().date(from: "2026-10-25T03:30:00Z")!
        XCTAssertNil(Holidays.current(on: late, region: "US", timeZone: TimeZone(identifier: "America/New_York")!))
        XCTAssertEqual(Holidays.current(on: late, region: "US", timeZone: utc), .halloween)
    }
}
