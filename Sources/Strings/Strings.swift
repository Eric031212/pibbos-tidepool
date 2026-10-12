/// Every user-visible string in Tidepool lives here (CLAUDE.md Section 6):
/// short, mostly lowercase English, chill tone. No string literals for the
/// user anywhere else in the code.
public enum Strings {
    public enum Menu {
        public static let music = "music? 🎧"
        public static let stopMusic = "stop music 🎧"
        public static let workMode = "work work, leave me alone :D"
        public static let quit = "bye 👋"
    }

    public enum Bubble {
        public static let musicInvitation = "music? 🎧"
        public static let goodbye = "ok ok, bye 👋"
        public static let napTime = "nap time zzz"
        public static let brb = "brb ☕"
        public static let snowCocoa = "snow! cocoa? ❄️"
    }

    public enum Errors {
        /// Shown in the log only (the app has no error UI).
        public static let skinFailedToLoad = "pibbo couldn't find his skin :("
    }
}
