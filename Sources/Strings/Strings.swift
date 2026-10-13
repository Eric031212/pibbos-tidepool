/// Every user-visible string in Tidepool lives here (CLAUDE.md Section 6):
/// short, a little otter-flavoured, with an emoji. No string literals for the
/// user anywhere else in the code. Every character must exist in the pixel
/// font (Tools/generate_sprites.py); a test checks this.
public enum Strings {
    public enum Menu {
        public static let music = "Music Time? 🎧"
        public static let stopMusic = "Tunes off 🐚"
        public static let workMode = "Dive time 🫧"
        public static let quit = "Swim away 👋"
    }

    public enum Bubble {
        public static let musicInvitation = "Music Time? 🎧"
        public static let goodbye = "Swim ya later 👋"
        public static let napTime = "Kelp nap zzz"
        public static let brb = "Brb, diving 🫧"
        public static let snowCocoa = "Snow! Cocoa? ❄️"
    }

    /// Everything above that is drawn in pixel text.
    public static let allPixelText: [String] = [
        Menu.music, Menu.stopMusic, Menu.workMode, Menu.quit,
        Bubble.musicInvitation, Bubble.goodbye, Bubble.napTime, Bubble.brb, Bubble.snowCocoa,
    ]

    public enum Errors {
        /// Shown in the log only (the app has no error UI).
        public static let skinFailedToLoad = "pibbo couldn't find his skin :("
    }
}
