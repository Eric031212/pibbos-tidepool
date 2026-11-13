import Foundation

/// Every game in the `Game time 🎮` list, in list order. Adding a game is one
/// entry here (plus its title in `Strings.Games` and its art in the sheet).
public enum GameCatalog {
    public struct Entry {
        /// Stable id: the title's key, the best score's key, the sheet prefix.
        public let id: String
        /// A fresh game; `random` returns a number in the given range.
        public let make: (_ random: @escaping (ClosedRange<Double>) -> Double) -> any Game
    }

    public static let all: [Entry] = [
        Entry(id: ShellCatch.id) { ShellCatch(random: $0) },
    ]

    public static func entry(id: String) -> Entry? {
        all.first { $0.id == id }
    }
}
