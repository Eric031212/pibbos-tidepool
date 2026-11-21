import Foundation

/// Pibbo's garden (v2.3): six plots where flowers grow with real days. Pure
/// rules and saved state; nothing ever wilts and nothing needs looking after
/// (no pet stats, CLAUDE.md Section 4). Watering only helps: a plot watered on
/// a day grows half a day extra that day.

public enum FlowerKind: String, CaseIterable, Codable, Sendable {
    case tulip, daisy, sunflower, lavender, poppy, bluebell

    /// Days from seed to bloom without any watering.
    public var bloomDays: Double {
        switch self {
        case .daisy: return 3
        case .tulip, .poppy: return 4
        case .lavender: return 5
        case .bluebell: return 6
        case .sunflower: return 7
        }
    }
}

public struct GardenPlot: Codable, Equatable, Sendable {
    public var kind: FlowerKind
    public var plantedAt: Date
    /// Growth (in days) it already had when its clock started: after picking,
    /// the plant goes back to a bud instead of starting over.
    public var headStart: Double
    /// Garden days it was watered on (each day counts once).
    public var wateredDays: [Int]

    public init(kind: FlowerKind, plantedAt: Date, headStart: Double = 0, wateredDays: [Int] = []) {
        self.kind = kind
        self.plantedAt = plantedAt
        self.headStart = headStart
        self.wateredDays = wateredDays
    }
}

public struct GardenState: Codable, Equatable, Sendable {
    public static let plotCount = 6
    public var plots: [GardenPlot?]
    /// The flower last picked for the pot by the pool, if any.
    public var potFlower: FlowerKind?
    /// How many flowers have been picked (so the pool can tell a fresh one).
    public var picks: Int

    public init(plots: [GardenPlot?] = Array(repeating: nil, count: GardenState.plotCount), potFlower: FlowerKind? = nil, picks: Int = 0) {
        self.plots = plots + Array(repeating: nil, count: max(0, GardenState.plotCount - plots.count))
        self.potFlower = potFlower
        self.picks = picks
    }
}

/// How long a garden day is: a real day, or much shorter in `--demo`.
public struct GardenClock: Sendable {
    public let dayLength: TimeInterval
    /// Shifts day boundaries to local midnight (seconds east of UTC).
    public let offset: TimeInterval

    public init(dayLength: TimeInterval = 86_400, offset: TimeInterval = 0) {
        self.dayLength = dayLength
        self.offset = offset
    }

    public func day(of date: Date) -> Int {
        Int(((date.timeIntervalSince1970 + offset) / dayLength).rounded(.down))
    }
}

public enum GardenRules {
    /// Growth stages: seed, sprout, leaves, bud, bloom.
    public static let stages = 5
    /// What a watered day adds, in days.
    public static let waterBonus = 0.5
    /// After picking, the plant keeps this share of its growth (a bud).
    public static let regrowShare = 0.75

    /// Days of growth so far.
    public static func growth(_ plot: GardenPlot, now: Date, clock: GardenClock) -> Double {
        let elapsed = max(0, now.timeIntervalSince(plot.plantedAt)) / clock.dayLength
        let firstDay = clock.day(of: plot.plantedAt), today = clock.day(of: now)
        let watered = Set(plot.wateredDays).filter { $0 >= firstDay && $0 <= today }.count
        return plot.headStart + elapsed + Double(watered) * waterBonus
    }

    /// 0 (seed) … 4 (in bloom).
    public static func stage(_ plot: GardenPlot, now: Date, clock: GardenClock) -> Int {
        let share = growth(plot, now: now, clock: clock) / plot.kind.bloomDays
        return share >= 1 ? stages - 1 : min(Int(share * Double(stages - 1)), stages - 2)
    }

    public static func isInBloom(_ plot: GardenPlot, now: Date, clock: GardenClock) -> Bool {
        stage(plot, now: now, clock: clock) == stages - 1
    }

    public static func wateredToday(_ plot: GardenPlot, now: Date, clock: GardenClock) -> Bool {
        plot.wateredDays.contains(clock.day(of: now))
    }

    public static func plant(_ kind: FlowerKind, in index: Int, of state: GardenState, now: Date) -> GardenState {
        guard state.plots.indices.contains(index), state.plots[index] == nil else { return state }
        var state = state
        state.plots[index] = GardenPlot(kind: kind, plantedAt: now)
        return state
    }

    /// Waters a plot. `helped` is false when it had already been watered today
    /// (it still gets the splash, just no extra growth).
    public static func water(_ index: Int, of state: GardenState, now: Date, clock: GardenClock) -> (state: GardenState, helped: Bool) {
        guard state.plots.indices.contains(index), var plot = state.plots[index] else { return (state, false) }
        let today = clock.day(of: now)
        guard !plot.wateredDays.contains(today) else { return (state, false) }
        plot.wateredDays = Array((plot.wateredDays + [today]).suffix(60))  // keep it small
        var state = state
        state.plots[index] = plot
        return (state, true)
    }

    /// Picks a flower in bloom for the pot by the pool; the plant goes back to a bud.
    public static func pick(_ index: Int, of state: GardenState, now: Date, clock: GardenClock) -> GardenState {
        guard state.plots.indices.contains(index), let plot = state.plots[index],
              isInBloom(plot, now: now, clock: clock) else { return state }
        var state = state
        state.plots[index] = GardenPlot(kind: plot.kind, plantedAt: now, headStart: plot.kind.bloomDays * regrowShare)
        state.potFlower = plot.kind
        state.picks += 1
        return state
    }
}

/// Where the garden is kept between openings (UserDefaults in the app).
public protocol GardenStore: AnyObject {
    func load() -> GardenState
    func save(_ state: GardenState)
}
