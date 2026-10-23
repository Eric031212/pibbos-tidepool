import Foundation
import World

/// Tidepool's behavior state machine (CLAUDE.md Section 5).
///
/// Pure and deterministic: it never reads the clock or calls system APIs.
/// Platform code feeds it `BrainEvent`s with the current time, reads `output`,
/// and keeps one timer for `nextDeadline`, delivering `.timerFired` when it
/// fires. Randomness is injected so tests can control it.
///
/// Visual priority, highest first: work mode (`submerged`) > music > sleep
/// (user away) > presence (hidden / peek / chill / random appearance).
/// Suspension (fullscreen, lock, sleep) hides everything on top of that.
public struct Brain {
    /// Source id of the built-in radio (`musicChanged(source:)`).
    public static let builtInSource = "built-in"

    public private(set) var output: BrainOutput

    private let config: BrainConfig
    private let random: (ClosedRange<Double>) -> Double

    /// Pibbo's own visibility cycle when nothing overrides it.
    private enum Presence: Equatable {
        case hidden
        case peek(until: Date)
        case chill(hideAt: Date)
        /// Random appearance; `nil` action shows `chill`.
        case appearance(action: String?, until: Date)

        var isChill: Bool { if case .chill = self { return true } else { return false } }
    }

    private var presence: Presence
    private var lastInteraction: Date
    private var hovering = false
    private var workMode = false
    private var suspendReasons: Set<SuspendReason> = []
    private var playingSources: Set<String> = []
    private var pendingStops: [String: Date] = [:]
    private var isUserAway = false
    private var timeOfDay: TimeOfDay = .day
    private var availableActions: [String] = []
    private var nextAppearance: Date?

    /// A small action played while Pibbo is out (`chill`).
    private var chillAction: (name: String, until: Date)?
    private var nextChillAction: Date?

    private var builtInMusicAvailable = false
    private var bubble: (kind: Bubble, until: Date)?
    private var lastInvitation: Date?

    /// Sources fading out right now; they stop at their `pendingStops` time.
    private var fadingSources: Set<String> = []
    /// Headphones-off clip after music stops.
    private var unplugUntil: Date?
    /// "theme - track" bubble while the built-in radio plays.
    private var nowPlayingUntil: Date?

    /// A short reaction to the user (backfloat after a rub, look at a splash).
    private var reaction: (name: String, until: Date)?
    /// The cursor is resting on Pibbo and he holds its "paw".
    private var holdingPaw = false

    /// When the next message in a bottle drifts in. The platform saves it, so
    /// the wait carries over across launches.
    public private(set) var nextBottle: Date
    /// While a bottle floats beside Pibbo: when it drifts off unopened.
    private var bottleUntil: Date?

    /// Starts in the launch flow: `peek` for a few seconds, then `chill`.
    /// `nextBottle`: a saved arrival time; nil schedules a fresh one.
    public init(config: BrainConfig = BrainConfig(), now: Date, nextBottle: Date? = nil,
                random: @escaping (ClosedRange<Double>) -> Double = { Double.random(in: $0) }) {
        self.config = config
        self.random = random
        self.nextBottle = nextBottle ?? now.addingTimeInterval(random(config.bottleInterval))
        presence = .peek(until: now.addingTimeInterval(config.launchPeek))
        lastInteraction = now
        output = BrainOutput(visual: .state(.peek), isSuspended: false, isWorkMode: false, bubble: nil)
        refreshOutput()
    }

    /// When the platform should deliver `.timerFired`; `nil` means no timer.
    /// Always `nil` while suspended, so nothing runs in the background.
    public var nextDeadline: Date? {
        guard suspendReasons.isEmpty else { return nil }
        var candidates = Array(pendingStops.values)
        if let bubble { candidates.append(bubble.until) }
        if let unplugUntil { candidates.append(unplugUntil) }
        if let reaction { candidates.append(reaction.until) }
        if let nowPlayingUntil, nowPlayingUntil != .distantFuture { candidates.append(nowPlayingUntil) }
        if let bottleUntil { candidates.append(bottleUntil) } else if !workMode { candidates.append(nextBottle) }
        switch presence {
        case .hidden:
            if let nextAppearance, !workMode { candidates.append(nextAppearance) }
        case .peek(let until), .appearance(_, let until):
            candidates.append(until)
        case .chill(let hideAt):
            candidates.append(hideAt)
            if let chillAction { candidates.append(chillAction.until) } else if let nextChillAction { candidates.append(nextChillAction) }
        }
        return candidates.min()
    }

    public mutating func handle(_ event: BrainEvent, at now: Date) {
        if suspendReasons.isEmpty { advance(to: now) }

        switch event {
        case .hoverBegan:
            guard !workMode else { break }
            hovering = true
            if isBuiltInPlaying { nowPlayingUntil = .distantFuture }
            isUserAway = false
            lastInteraction = now
            switch presence {
            case .hidden: setPresence(.peek(until: now.addingTimeInterval(config.hoverPeek)), at: now)
            case .peek: break
            case .chill, .appearance: setPresence(.chill(hideAt: now.addingTimeInterval(config.hideAfterNoInteraction)), at: now)
            }

        case .hoverEnded:
            guard hovering else { break }
            hovering = false
            if nowPlayingUntil == .distantFuture { nowPlayingUntil = now.addingTimeInterval(config.nowPlayingAfterHover) }
            lastInteraction = now
            if presence.isChill {
                setPresence(.chill(hideAt: now.addingTimeInterval(config.hideAfterNoInteraction)), at: now)
            }

        case .clicked:
            workMode = false
            isUserAway = false
            bubble = nil  // the menu takes the bubble's place
            lastInteraction = now
            setPresence(.chill(hideAt: now.addingTimeInterval(config.hideAfterNoInteraction)), at: now)

        case .workModeEntered:
            workMode = true
            hovering = false
            bubble = nil
            setPresence(.hidden, at: now)
            nextAppearance = nil

        case .userIdle(let seconds):
            let threshold = timeOfDay == .night ? config.idleBeforeSleepAtNight : config.idleBeforeSleep
            let wasAway = isUserAway
            isUserAway = seconds >= threshold
            if wasAway && !isUserAway {
                // Wake up quietly: back to hidden rather than popping up.
                becomeHidden(at: now)
            }

        case .musicChanged(let source, let playing):
            if playing {
                playingSources.insert(source)
                pendingStops[source] = nil
                fadingSources.remove(source)
                unplugUntil = nil
                bubble = nil
            } else if playingSources.contains(source), !fadingSources.contains(source) {
                pendingStops[source] = now.addingTimeInterval(config.musicStopDebounce)
            }

        case .musicFadingOut(let source, let duration):
            guard playingSources.contains(source) else { break }
            fadingSources.insert(source)
            pendingStops[source] = now.addingTimeInterval(duration)
            if source == Self.builtInSource { nowPlayingUntil = nil }

        case .builtInTrackStarted:
            nowPlayingUntil = hovering ? .distantFuture : now.addingTimeInterval(config.nowPlayingDuration)

        case .rubbed:
            guard !workMode else { break }
            interact(at: now)
            holdingPaw = false
            reaction = ("backfloat", now.addingTimeInterval(config.backfloatDuration))

        case .holdBegan:
            guard !workMode else { break }
            interact(at: now)
            holdingPaw = true

        case .holdEnded:
            holdingPaw = false

        case .splashed:
            // Only reachable while the flower (and so Pibbo) is showing.
            guard !workMode else { break }
            interact(at: now)
            reaction = ("look", now.addingTimeInterval(config.lookDuration))

        case .suspended(let reason):
            if suspendReasons.isEmpty {
                hovering = false
                bubble = nil
                unplugUntil = nil
                nowPlayingUntil = nil
                reaction = nil
                holdingPaw = false
                setPresence(.hidden, at: now)
                nextAppearance = nil
            }
            suspendReasons.insert(reason)

        case .resumed(let reason):
            guard suspendReasons.remove(reason) != nil, suspendReasons.isEmpty else { break }
            advance(to: now)  // settle music stops that came due while suspended
            becomeHidden(at: now)

        case .timeOfDayChanged(let newValue):
            timeOfDay = newValue

        case .availableActionsChanged(let actions):
            availableActions = actions

        case .builtInMusicAvailable(let available):
            builtInMusicAvailable = available

        case .bottleClicked:
            guard bottleUntil != nil, !workMode else { break }
            bottleUntil = nil
            nextBottle = now.addingTimeInterval(random(config.bottleInterval))
            interact(at: now)
            holdingPaw = false
            reaction = ("note", now.addingTimeInterval(config.noteDuration))
            bubble = (.note(pick: random(0...0.999_999)), now.addingTimeInterval(config.noteDuration))

        case .bubbleClicked:
            bubble = nil

        case .timerFired:
            break  // advance(to:) above already did the work
        }

        refreshOutput()
    }

    // MARK: - Private

    /// Any direct play with Pibbo: wakes him, keeps him out, restarts the hide timer.
    private mutating func interact(at now: Date) {
        isUserAway = false
        lastInteraction = now
        setPresence(.chill(hideAt: now.addingTimeInterval(config.hideAfterNoInteraction)), at: now)
    }

    private var isBuiltInPlaying: Bool {
        playingSources.contains(Self.builtInSource) && !fadingSources.contains(Self.builtInSource)
    }

    private var canAppearOnHisOwn: Bool {
        !workMode && suspendReasons.isEmpty && playingSources.isEmpty && !isUserAway
    }

    /// Changes presence, starting or clearing the small-action cycle that
    /// runs while Pibbo is out.
    private mutating func setPresence(_ new: Presence, at now: Date) {
        if new.isChill && !presence.isChill {
            nextChillAction = now.addingTimeInterval(random(config.chillActionInterval))
        } else if !new.isChill {
            chillAction = nil
            nextChillAction = nil
        }
        presence = new
    }

    private mutating func becomeHidden(at now: Date) {
        setPresence(.hidden, at: now)
        if !workMode {
            nextAppearance = now.addingTimeInterval(random(config.randomAppearanceInterval))
        }
    }

    /// Applies every deadline that is due at `now`, in order.
    private mutating func advance(to now: Date) {
        for (source, at) in pendingStops.sorted(by: { $0.value < $1.value }) where at <= now {
            pendingStops[source] = nil
            playingSources.remove(source)
            let faded = fadingSources.remove(source) != nil
            if playingSources.isEmpty && !faded {
                // A plain stop: take the headphones off now. (A fade already showed it.)
                unplugUntil = at.addingTimeInterval(config.unplugDuration)
            }
        }
        if !isBuiltInPlaying { nowPlayingUntil = nil }
        if let until = unplugUntil, until <= now { unplugUntil = nil }
        if let current = reaction, current.until <= now { reaction = nil }
        if let until = nowPlayingUntil, until <= now { nowPlayingUntil = nil }
        if let current = bubble, current.until <= now { bubble = nil }
        if let until = bottleUntil, until <= now {
            // Nobody opened it: it drifts off, and another comes in a few days.
            bottleUntil = nil
            nextBottle = until.addingTimeInterval(random(config.bottleInterval))
        }
        if bottleUntil == nil, nextBottle <= now, !workMode {
            bottleUntil = now.addingTimeInterval(config.bottleStay)
        }

        // A few passes cover chains such as peek → chill → hidden after a long gap.
        for _ in 0..<4 {
            switch presence {
            case .peek(let until) where until <= now:
                setPresence(.chill(hideAt: lastInteraction.addingTimeInterval(config.hideAfterNoInteraction)), at: until)
            case .chill(let hideAt) where hideAt <= now:
                if hovering {
                    presence = .chill(hideAt: now.addingTimeInterval(config.hideAfterNoInteraction))
                } else {
                    becomeHidden(at: hideAt)
                }
            case .chill:
                advanceChillAction(to: now)
                return
            case .appearance(_, let until) where until <= now:
                becomeHidden(at: until)
            case .hidden:
                guard let due = nextAppearance, due <= now, !workMode else { return }
                let isStale = now.timeIntervalSince(due) > config.actionDuration.upperBound
                if canAppearOnHisOwn && !isStale {
                    appear(at: now)
                } else {
                    nextAppearance = now.addingTimeInterval(random(config.randomAppearanceInterval))
                }
            default:
                return
            }
        }
    }

    private mutating func advanceChillAction(to now: Date) {
        if let action = chillAction {
            guard action.until <= now else { return }
            chillAction = nil
            nextChillAction = now.addingTimeInterval(random(config.chillActionInterval))
        } else if let due = nextChillAction, due <= now {
            if let name = pickAction() {
                chillAction = (name, now.addingTimeInterval(random(config.actionDuration)))
                nextChillAction = nil
            } else {
                nextChillAction = now.addingTimeInterval(random(config.chillActionInterval))
            }
        }
    }

    /// A random appearance, sometimes with the music invitation.
    private mutating func appear(at now: Date) {
        var until = now.addingTimeInterval(random(config.actionDuration))
        if shouldInviteToMusic(at: now) {
            let bubbleUntil = now.addingTimeInterval(config.bubbleDuration)
            bubble = (.musicInvitation, bubbleUntil)
            lastInvitation = now
            until = max(until, bubbleUntil)  // stay out while the bubble is up
        }
        setPresence(.appearance(action: pickAction(), until: until), at: now)
    }

    private func shouldInviteToMusic(at now: Date) -> Bool {
        guard builtInMusicAvailable, playingSources.isEmpty, !workMode else { return false }
        if let lastInvitation, now.timeIntervalSince(lastInvitation) < config.musicInvitationCooldown { return false }
        return random(0...1) < config.musicInvitationChance
    }

    private func pickAction() -> String? {
        guard !availableActions.isEmpty else { return nil }
        let index = Int(random(0...Double(availableActions.count - 1)).rounded())
        return availableActions[min(max(index, 0), availableActions.count - 1)]
    }

    private mutating func refreshOutput() {
        let visual: PetVisual
        let allFading = !playingSources.isEmpty && playingSources.isSubset(of: fadingSources)
        if workMode {
            visual = .submerged
        } else if allFading || unplugUntil != nil {
            visual = .action("unplug")
        } else if holdingPaw {
            visual = .action("holdpaw")
        } else if let reaction {
            visual = .action(reaction.name)
        } else if !playingSources.isEmpty {
            visual = .state(.music)
        } else if isUserAway {
            visual = .state(.sleep)
        } else {
            switch presence {
            case .hidden: visual = .state(.hidden)
            case .peek: visual = .state(.peek)
            case .chill: visual = chillAction.map { .action($0.name) } ?? .state(.chill)
            case .appearance(let action, _): visual = action.map(PetVisual.action) ?? .state(.chill)
            }
        }
        var shown: Bubble?
        if suspendReasons.isEmpty && !workMode {
            if let bubble, case .note = bubble.kind {
                shown = bubble.kind  // a note shows even over music
            } else if playingSources.isEmpty, let bubble {
                shown = bubble.kind
            } else if isBuiltInPlaying, nowPlayingUntil != nil {
                shown = .nowPlaying
            }
        }
        output = BrainOutput(visual: visual, isSuspended: !suspendReasons.isEmpty, isWorkMode: workMode, bubble: shown,
                             bottle: bottleUntil != nil && suspendReasons.isEmpty && !workMode)
    }
}
