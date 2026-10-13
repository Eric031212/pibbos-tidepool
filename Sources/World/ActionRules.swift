import Foundation

/// Which small actions fit the moment. Returns a weighted list (an action
/// listed twice is twice as likely); the caller intersects it with the
/// actions the skin actually provides.
public enum ActionRules {
    /// Everyday idle actions.
    public static let idle = ["water", "crack", "groom"]

    public static func actions(for context: WorldContext) -> [String] {
        var result: [String] = []

        switch context.weather {
        case .storm:
            return ["huddle", "huddle", "groom"]  // no watering or sunbathing in a storm
        case .rain:
            result += ["raindrops", "raindrops"]
        case .snow:
            result += ["cocoa", "cocoa"]
        case .clear:
            if context.timeOfDay == .day && context.season != .winter { result += ["sunbathe", "sunbathe"] }
            if context.timeOfDay == .night { result += ["stargaze", "stargaze"] }
        case .cloudy, nil:
            break
        }

        switch context.timeOfDay {
        case .dawn: result += ["stretch", "yawn"]
        case .dusk: result += ["yawn"]
        case .night: result += ["yawn"]
        case .day: break
        }

        switch context.season {
        case .spring: result += ["petal"]
        case .autumn: result += ["leaf"]
        case .winter where context.weather != .rain: result += ["cocoa"]
        default: break
        }

        // Watering at night or in the rain would be odd.
        let everyday = context.timeOfDay == .night || context.weather == .rain ? ["crack", "groom"] : idle
        return result + everyday
    }
}

/// The flower beside Pibbo grows with real days since the first launch: no
/// care needed, never wilts (decided 2026-10-12).
public enum Garden {
    /// Day thresholds for each stage: seed, sprout, leaves, bud, bloom, full bloom.
    public static let stageDays: [Double] = [0, 1, 3, 6, 10, 14]

    public static func stage(daysSinceFirstLaunch days: Double, stageCount: Int) -> Int {
        guard stageCount > 0 else { return 0 }
        let reached = stageDays.lastIndex(where: { days >= $0 }) ?? 0
        return min(reached, stageCount - 1)
    }
}
