import Foundation

/// What Pibbo does while he listens (v2.2): now and then he puts the plain
/// headphone bob aside for a move. Each radio theme brings moves in its own
/// style (theme.json "moves"); the general ones fit any music, also Apple Music.
public enum MusicMoves {
    /// Moves for any music: swaying, singing along, a little bongo, clapping,
    /// a shimmy, humming, blowing bubbles.
    public static let general = ["sway", "sing", "drum", "clap", "shimmy", "hum", "bubbles"]
    /// Moves that end with a little bubble (a game won, a tune finished).
    public static let finales: Set<String> = ["game", "piano", "strum"]
    /// Chance that a move comes from the theme rather than the general ones.
    public static let themedShare = 0.6

    /// Picks the next move. `roll` and `index` are random numbers in 0..<1.
    public static func pick(themed: [String], general: [String], roll: Double, index: Double) -> String? {
        let pool = !themed.isEmpty && (roll < themedShare || general.isEmpty) ? themed : general
        guard !pool.isEmpty else { return nil }
        return pool[min(Int(index * Double(pool.count)), pool.count - 1)]
    }
}
