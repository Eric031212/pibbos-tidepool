import Foundation

/// Who may drop by the tide pool right now (v1.0). Like `ActionRules`, a
/// weighted list (a name listed three times is three times as likely); the
/// caller keeps only the visitors the skin draws.
public enum Visitors {
    public static func candidates(for context: WorldContext) -> [String] {
        var result: [String] = []
        let wet = context.weather == .rain || context.weather == .storm
        let night = context.timeOfDay == .night
        if !night && !wet && context.weather != .snow { result += ["crab", "crab", "crab"] }   // shore walks on dry days
        if !night && !wet { result += ["seagull", "seagull", "seagull"] }                      // no flying in the rain
        if context.weather != .storm && context.weather != .snow { result += ["fish", "fish", "fish"] }
        if context.weather != .storm { result += ["friend"] }                                  // the rarest visit
        return result
    }

    /// What Pibbo does while someone visits: he looks at the shore folk, and
    /// reaches out to hold paws with his friend.
    public static func reaction(to visitor: String) -> String {
        visitor == "friend" ? "friendpaw" : "look"
    }
}

/// The seagull's little story (v1.0): after a few visits it brings Pibbo a
/// present, which then stays on the meadow rock for good. No counter is ever
/// shown; one day there's simply a feather.
public enum SeagullGift {
    /// Ordinary visits before the one that brings the gift.
    public static let visitsBeforeGift = 4

    /// The visit to play when the seagull comes: "seagullGift" on its fifth
    /// visit (once), "seagull" otherwise.
    public static func visit(seagullVisitsSoFar visits: Int, hasGift: Bool) -> String {
        !hasGift && visits >= visitsBeforeGift ? "seagullGift" : "seagull"
    }
}
