import XCTest
@testable import World

final class GreetingTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// 2026-11-16 is a Monday; 2026-11-14 a Saturday.
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func greet(_ now: Date, away: TimeInterval?, memory: GreetingMemory = GreetingMemory(),
                       first: Bool = false, weather: Weather? = .clear) -> (Greeting?, GreetingMemory) {
        Greetings.onReturn(at: now, awayFor: away, firstLaunch: first, weather: weather, memory: memory, calendar: calendar)
    }

    func testTheFirstLaunchSaysHelloAndCountsAsToday() {
        let (g, memory) = greet(date(16, 9), away: nil, first: true)
        XCTAssertEqual(g, .hello)
        XCTAssertNil(greet(date(16, 9, 30), away: nil, memory: memory).0, "no morning after the hello")
    }

    func testGoodMorningOnceADayWithTheWeather() {
        let (g, memory) = greet(date(16, 8), away: 9 * 3600, weather: .rain)
        XCTAssertEqual(g, .morning(.rain))
        XCTAssertNil(greet(date(16, 9), away: 30 * 60, memory: memory).0, "only once a day")
        XCTAssertEqual(greet(date(17, 8), away: 9 * 3600, memory: memory).0, .morning(.clear), "again tomorrow")
    }

    func testALaunchAtLoginInTheMorningCountsAsComingBack() {
        XCTAssertEqual(greet(date(16, 7), away: nil, weather: nil).0, .morning(nil))
    }

    func testWeekendMornings() {
        XCTAssertEqual(greet(date(14, 10), away: 10 * 3600).0, .weekend(saturday: true))
        XCTAssertEqual(greet(date(15, 10), away: 10 * 3600).0, .weekend(saturday: false))
    }

    func testNoMorningInTheAfternoonOrAfterAShortBreak() {
        XCTAssertNil(greet(date(16, 9), away: 20 * 60).0, "a short break isn't a new morning")
        XCTAssertEqual(greet(date(16, 14), away: 5 * 3600).0, .welcomeBack, "afternoon: welcome back instead")
    }

    func testWelcomeBackAtMostTwiceADay() {
        var memory = GreetingMemory(morningDay: Greetings.dayKey(date(16, 8), calendar: calendar))
        var said: [Greeting?] = []
        for hour in [11, 14, 17] {
            let result = greet(date(16, hour), away: 2.5 * 3600, memory: memory)
            said.append(result.0)
            memory = result.1
        }
        XCTAssertEqual(said, [.welcomeBack, .welcomeBack, nil])
        XCTAssertEqual(greet(date(17, 15), away: 3 * 3600, memory: memory).0, .welcomeBack, "a new day")
    }

    func testNightOwlOncePerNightAcrossMidnight() {
        let (g, memory) = Greetings.nightOwl(at: date(16, 23, 10), memory: GreetingMemory(), calendar: calendar)
        XCTAssertEqual(g, .nightOwl)
        XCTAssertEqual(g?.action, "cocoa")
        XCTAssertNil(Greetings.nightOwl(at: date(17, 1), memory: memory, calendar: calendar).0, "after midnight it's the same night")
        XCTAssertEqual(Greetings.nightOwl(at: date(17, 23, 30), memory: memory, calendar: calendar).0, .nightOwl)
        XCTAssertNil(Greetings.nightOwl(at: date(17, 21), memory: GreetingMemory(), calendar: calendar).0, "not before 23:00")
    }

    func testComingBackLateIsANightOwlNotAWelcome() {
        XCTAssertEqual(greet(date(16, 23, 30), away: 3 * 3600).0, .nightOwl)
    }
}

final class OccasionTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ month: Int, _ day: Int, year: Int = 2026, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testANewSeasonTakesTheMorningsPlaceButTheFirstSightingIsOnlyNoted() {
        var memory = GreetingMemory()
        var (g, m) = Greetings.onReturn(at: date(11, 16), awayFor: 9 * 3600, firstLaunch: false, weather: .clear,
                                         memory: memory, calendar: calendar, daysTogether: 30, season: .autumn)
        XCTAssertEqual(g, .morning(.clear), "an update in mid-autumn doesn't announce autumn")
        memory = m
        (g, m) = Greetings.onReturn(at: date(12, 1), awayFor: 9 * 3600, firstLaunch: false, weather: .clear,
                                     memory: memory, calendar: calendar, daysTogether: 45, season: .winter)
        XCTAssertEqual(g, .newSeason(.winter))
        XCTAssertEqual(g?.action, "cocoa")
        (g, _) = Greetings.onReturn(at: date(12, 2), awayFor: 9 * 3600, firstLaunch: false, weather: .clear,
                                     memory: m, calendar: calendar, daysTogether: 46, season: .winter)
        XCTAssertEqual(g, .morning(.clear), "only on the first day")
    }

    func testTogetherMilestones() {
        XCTAssertEqual(Greetings.milestone(forDay: 100), 100)
        XCTAssertEqual(Greetings.milestone(forDay: 103), 100)
        XCTAssertNil(Greetings.milestone(forDay: 110), "too late for a party")
        XCTAssertEqual(Greetings.milestone(forDay: 365), 365)
        XCTAssertEqual(Greetings.milestone(forDay: 731), 730)
        XCTAssertNil(Greetings.milestone(forDay: 99))

        let (g, m) = Greetings.occasion(at: date(3, 1), daysTogether: 101, season: .spring, memory: GreetingMemory(season: "winter"))
        XCTAssertEqual(g, .together(days: 100), "the milestone wins over the new season")
        XCTAssertEqual(g?.action, "backfloat")
        XCTAssertNil(Greetings.occasion(at: date(3, 2), daysTogether: 102, season: .spring, memory: m).0, "once")
    }

    func testFirstSnowOncePerWinterAcrossNewYear() {
        let (g, m) = Greetings.snowStarted(at: date(12, 20), memory: GreetingMemory(), calendar: calendar)
        XCTAssertEqual(g, .firstSnow)
        XCTAssertNil(Greetings.snowStarted(at: date(1, 15, year: 2027), memory: m, calendar: calendar).0, "same winter")
        XCTAssertEqual(Greetings.snowStarted(at: date(12, 5, year: 2027), memory: m, calendar: calendar).0, .firstSnow, "next winter")
    }

    func testTheHelloNotesTheSeason() {
        let (_, m) = Greetings.onReturn(at: date(11, 16), awayFor: nil, firstLaunch: true, weather: nil,
                                         memory: GreetingMemory(), calendar: calendar, season: .autumn)
        XCTAssertEqual(m.season, "autumn")
    }
}
