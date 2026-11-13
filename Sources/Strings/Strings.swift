/// Every user-visible string in Tidepool lives here (CLAUDE.md Section 6):
/// short, a little otter-flavoured, with an emoji. No string literals for the
/// user anywhere else in the code. Every character must exist in the pixel
/// font (Tools/generate_sprites.py); a test checks this.
public enum Strings {
    public enum Menu {
        public static let music = "Music Time? 🎧"
        public static let stopMusic = "Tunes off 🐚"
        public static let games = "Game time 🎮"
        public static let workMode = "Dive time 🫧"
        public static let quit = "Swim away 👋"
    }

    public enum Bubble {
        public static let musicInvitation = "Music Time? 🎧"
        public static let goodbye = "Swim ya later 👋"
        public static let napTime = "Kelp nap zzz"
        public static let brb = "Brb, diving 🫧"
        public static let snowCocoa = "Snow! Cocoa? ❄️"
        public static let wish = "Made a wish ✨"
        public static let gg = "GG! ✨"
    }

    /// The little games (`Game time 🎮`). Titles by `GameCatalog` id.
    public enum Games {
        public static let titles: [String: String] = [
            "shellCatch": "Shell Catch 🐚",
        ]
        public static let clickToPlay = "Click to play 🎮"
        public static let escToClose = "Esc to close 👋"
        public static let paused = "Paused 🫧"
        public static let newBest = "New best! ✨"
        public static func score(_ value: Int) -> String { "Score \(value)" }
        public static func best(_ value: Int) -> String { "Best \(value)" }
    }

    /// Notes found in a message in a bottle; one is picked at random.
    public static let bottleNotes: [String] = [
        "The sea says hi 🌊",
        "Float on, friend 🫧",
        "Tea break? ☕",
        "Someone far away waves 👋",
        "Found a nice shell 🐚",
        "Tides come, tides go 🌊",
        "Hum a little tune ♪",
        "No rush today 🫧",
        "The kelp says hello 🐚",
        "Stretch your paws 👋",
        "It's snowing somewhere ❄️",
        "You float nicely 🫧",
        "Rest is good too ☕",
        "A wave, just for you 🌊",
        "Keep it slow 🐚",
        "Listen to the water ♪",
        "Cocoa later? ☕",
        "Hello from the deep 🫧",
    ]

    /// Dream bubbles: what Pibbo dreams of, by memory token. Icons only (a
    /// dream has no words), each after a thought bubble.
    public static let dreams: [String: String] = [
        "crab": "💭 🦀", "seagull": "💭 🐦", "fish": "💭 🐟", "friend": "💭 🦦",
        "bottle": "💭 🍾", "star": "💭 ✨", "music": "💭 🎧",
        "shell": "💭 🐚", "flower": "💭 🌷", "bubbles": "💭 🫧",
    ]
    /// What he dreams of before he has seen anything.
    public static let everydayDreams = ["shell", "flower", "bubbles"]

    /// The note for Brain's `pick` (0..<1).
    public static func bottleNote(pick: Double) -> String {
        let index = Int(pick * Double(bottleNotes.count))
        return bottleNotes[min(max(index, 0), bottleNotes.count - 1)]
    }

    /// Everything above that is drawn in pixel text.
    public static let allPixelText: [String] = [
        Menu.music, Menu.stopMusic, Menu.games, Menu.workMode, Menu.quit,
        Games.clickToPlay, Games.escToClose, Games.paused, Games.newBest, Games.score(1_234_567_890), Games.best(1_234_567_890),
        Bubble.musicInvitation, Bubble.goodbye, Bubble.napTime, Bubble.brb, Bubble.snowCocoa, Bubble.wish, Bubble.gg,
    ] + bottleNotes + dreams.values.sorted() + Games.titles.values.sorted()

    public enum Errors {
        /// Shown in the log only (the app has no error UI).
        public static let skinFailedToLoad = "pibbo couldn't find his skin :("
    }
}
