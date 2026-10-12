import Foundation

/// The five states every skin must provide (CLAUDE.md Section 3).
public enum PetState: String, CaseIterable, Sendable {
    case hidden, peek, chill, music, sleep
}

/// What Pibbo should show. The renderer resolves missing optional actions
/// through the content pack's fallbacks.
public enum PetVisual: Equatable, Sendable {
    case state(PetState)
    /// An optional skin action, e.g. "stretch". Falls back to `chill`.
    case action(String)
    /// Work mode look. Falls back to `hidden`.
    case submerged
}

/// Why Pibbo must be fully hidden with everything paused.
public enum SuspendReason: Hashable, Sendable {
    case fullscreen, locked, asleep
}

public enum TimeOfDay: Sendable {
    case dawn, day, dusk, night
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
    case suspended(SuspendReason)
    case resumed(SuspendReason)
    case timeOfDayChanged(TimeOfDay)
    /// Optional actions that fit the current context (time, weather, season,
    /// holiday) and that the skin provides.
    case availableActionsChanged([String])
    /// The platform's single timer reached `Brain.nextDeadline`.
    case timerFired
}

public struct BrainOutput: Equatable, Sendable {
    public var visual: PetVisual
    /// True while fullscreen / locked / asleep: hide the window and pause
    /// all animations and timers.
    public var isSuspended: Bool
    public var isWorkMode: Bool
}

/// Timing values (seconds). Starting points from CLAUDE.md Section 5, to be tuned.
public struct BrainConfig: Sendable {
    public var launchPeek: TimeInterval = 5
    public var hoverPeek: TimeInterval = 1.5
    public var hideAfterNoInteraction: TimeInterval = 150
    public var randomAppearanceInterval: ClosedRange<TimeInterval> = (30 * 60)...(60 * 60)
    public var actionDuration: ClosedRange<TimeInterval> = 5...10
    public var idleBeforeSleep: TimeInterval = 10 * 60
    /// Late night: stronger tendency toward sleep.
    public var idleBeforeSleepAtNight: TimeInterval = 5 * 60
    /// Ignore a stop shorter than this (Apple Music sends a brief `Stopped`
    /// between tracks, spike 1).
    public var musicStopDebounce: TimeInterval = 1.5

    public init() {}
}
