import Foundation
import World

/// The five states every skin must provide (CLAUDE.md Section 3).
public enum PetState: String, CaseIterable, Sendable {
    case hidden, peek, chill, music, sleep
}

/// What Pibbo should show. The renderer resolves missing optional actions
/// through the content pack's fallbacks.
public enum PetVisual: Equatable, Sendable {
    case state(PetState)
    /// An optional skin action, e.g. "water". Falls back to `chill`.
    case action(String)
    /// Work mode look. Falls back to `hidden`.
    case submerged
}

/// A speech bubble above Pibbo.
public enum Bubble: Equatable, Sendable {
    /// `Music Time? 🎧`: clicking it starts the built-in lofi.
    case musicInvitation
    /// Scrolling "theme - track" while the built-in lofi plays.
    case nowPlaying
    /// The note from a message in a bottle. `pick` in 0..<1 chooses which of
    /// the string table's notes (Brain doesn't know the strings).
    case note(pick: Double)
    /// `Made a wish ✨` after wishing on a shooting star.
    case wish

    /// Bubbles that answer something the user just did show even over music.
    var showsOverMusic: Bool {
        switch self {
        case .note, .wish: return true
        case .musicInvitation, .nowPlaying: return false
        }
    }
}

/// Why Pibbo must be fully hidden with everything paused.
public enum SuspendReason: Hashable, Sendable {
    case fullscreen, locked, asleep
}

/// Everything Brain reacts to. Platform code turns system signals into these.
public enum BrainEvent: Equatable, Sendable {
    case hoverBegan
    case hoverEnded
    /// A click on Pibbo. In work mode it ends work mode; otherwise the app
    /// also opens the menu.
    case clicked
    case workModeEntered
    /// Periodic sample of seconds since the last keyboard/mouse input.
    case userIdle(seconds: TimeInterval)
    /// An external or built-in music source started or stopped.
    case musicChanged(source: String, playing: Bool)
    /// A source is fading out and stops after `duration`: Pibbo takes his
    /// headphones off in sync with the fade.
    case musicFadingOut(source: String, duration: TimeInterval)
    /// The built-in radio started a new track.
    case builtInTrackStarted
    /// The mouse rubbed back and forth over Pibbo: he rolls onto his back.
    case rubbed
    /// The mouse rests still on Pibbo: he holds your "paw" until it moves.
    case holdBegan
    case holdEnded
    /// A click on the water beside him: he turns to look.
    case splashed
    /// A click on the message in a bottle: Pibbo comes out and reads the note.
    case bottleClicked
    /// Whether it is a clear night (shooting stars only fall then).
    case clearNightChanged(Bool)
    /// A click on Pibbo right after a shooting star: he makes a wish (instead
    /// of the menu opening). Platform sends it while `output.shootingStar`.
    case wished
    case suspended(SuspendReason)
    case resumed(SuspendReason)
    case timeOfDayChanged(TimeOfDay)
    /// Optional actions that fit the current context (time, weather, season)
    /// and that the skin provides. Duplicates make an action more likely.
    case availableActionsChanged([String])
    /// Whether built-in lofi tracks exist (no invitation without them).
    case builtInMusicAvailable(Bool)
    case bubbleClicked
    /// The platform's single timer reached `Brain.nextDeadline`.
    case timerFired
}

public struct BrainOutput: Equatable, Sendable {
    public var visual: PetVisual
    /// True while fullscreen / locked / asleep: hide the window and pause
    /// all animations and timers.
    public var isSuspended: Bool
    public var isWorkMode: Bool
    public var bubble: Bubble?
    /// A message in a bottle is floating beside Pibbo (shown even while he hides).
    public var bottle: Bool = false
    /// A shooting star just fell: the platform plays it once, and a click on
    /// Pibbo while this is true is a wish.
    public var shootingStar: Bool = false
}

/// Timing values (seconds). Starting points from CLAUDE.md Section 5, to be tuned.
public struct BrainConfig: Sendable {
    public var launchPeek: TimeInterval = 5
    public var hoverPeek: TimeInterval = 1.5
    public var hideAfterNoInteraction: TimeInterval = 150
    public var randomAppearanceInterval: ClosedRange<TimeInterval> = (30 * 60)...(60 * 60)
    public var actionDuration: ClosedRange<TimeInterval> = 5...10
    /// While Pibbo is out (`chill`), he does a small action this often.
    public var chillActionInterval: ClosedRange<TimeInterval> = 25...50
    public var idleBeforeSleep: TimeInterval = 10 * 60
    /// Late night: stronger tendency toward sleep.
    public var idleBeforeSleepAtNight: TimeInterval = 5 * 60
    /// Ignore a stop shorter than this (Apple Music sends a brief `Stopped`
    /// between tracks, spike 1).
    public var musicStopDebounce: TimeInterval = 1.5
    /// Chance that a random appearance comes with `music? 🎧`. With one
    /// appearance every 30–60 min and the hourly cap, that is roughly one
    /// invitation every 2–3 hours: rare on purpose.
    public var musicInvitationChance: Double = 0.3
    /// At most one invitation per hour (CLAUDE.md Section 5).
    public var musicInvitationCooldown: TimeInterval = 60 * 60
    public var bubbleDuration: TimeInterval = 6
    /// How long "theme - track" shows when a built-in track starts.
    public var nowPlayingDuration: TimeInterval = 15
    /// It lingers this long after the mouse leaves Pibbo.
    public var nowPlayingAfterHover: TimeInterval = 3
    /// The `unplug` clip (headphones off) when music stops.
    public var unplugDuration: TimeInterval = 1.6
    /// Floating on his back after a rub.
    public var backfloatDuration: TimeInterval = 4
    /// Looking at a splash.
    public var lookDuration: TimeInterval = 1.5
    /// A message in a bottle drifts in every few days...
    public var bottleInterval: ClosedRange<TimeInterval> = (2 * 86_400)...(4 * 86_400)
    /// ...and drifts off again if nobody opens it.
    public var bottleStay: TimeInterval = 30 * 60
    /// How long Pibbo reads the note (and its bubble stays up).
    public var noteDuration: TimeInterval = 7
    /// On clear nights, a shooting star now and then.
    public var shootingStarInterval: ClosedRange<TimeInterval> = (20 * 60)...(60 * 60)
    /// How long after a star a click on Pibbo still counts as a wish.
    public var wishWindow: TimeInterval = 6
    /// Pibbo wishing (and the `Made a wish ✨` bubble).
    public var wishDuration: TimeInterval = 4

    public init() {}

    /// Everything sped up, for trying the app out (`--demo`).
    public static var demo: BrainConfig {
        var config = BrainConfig()
        config.hideAfterNoInteraction = 20
        config.randomAppearanceInterval = 20...40
        config.actionDuration = 5...8
        config.chillActionInterval = 6...10
        config.idleBeforeSleep = 120
        config.idleBeforeSleepAtNight = 60
        config.musicInvitationChance = 1
        config.musicInvitationCooldown = 60
        config.bubbleDuration = 8
        config.bottleInterval = 40...70
        config.bottleStay = 45
        config.shootingStarInterval = 15...25
        return config
    }
}
