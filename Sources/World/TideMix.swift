import Foundation

/// Tide sounds (v2.0): which ambient loops play, and how loud, for the pool
/// right now. Pure; the platform crossfades to whatever this returns.
public enum TideMix {
    /// Loop name → volume (0…1).
    public static func layers(for context: WorldContext) -> [String: Float] {
        let night = context.timeOfDay == .night
        switch context.weather {
        case .rain, .storm:
            return ["rain": 1, night ? "nightwaves" : "waves": 0.25]
        case .snow:
            return ["wind": 0.8, night ? "nightwaves" : "waves": 0.2]
        default:
            guard night else { return ["waves": 1] }
            return context.season == .summer ? ["nightwaves": 1, "crickets": 0.6] : ["nightwaves": 1]
        }
    }
}
