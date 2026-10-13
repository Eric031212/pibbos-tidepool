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

    /// Starts in the launch flow: `peek` for a few seconds, then `chill`.
    public init(config: BrainConfig = BrainConfig(), now: Date,
                random: @escaping (ClosedRange<Double>) -> Double = { Double.random(in: $0) }) {
        self.config = config
        self.random = random
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
                bubble = nil
            } else if playingSources.contains(source) {
                pendingStops[source] = now.addingTimeInterval(config.musicStopDebounce)
            }

        case .suspended(let reason):
            if suspendReasons.isEmpty {
                hovering = false
                bubble = nil
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

        case .bubbleClicked:
            bubble = nil

        case .timerFired:
            break  // advance(to:) above already did the work
        }

        refreshOutput()
    }

    // MARK: - Private

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
        for (source, at) in pendingStops where at <= now {
            pendingStops[source] = nil
            playingSources.remove(source)
        }
        if let current = bubble, current.until <= now { bubble = nil }

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
        if workMode {
            visual = .submerged
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
        let showsBubble = suspendReasons.isEmpty && !workMode && playingSources.isEmpty
        output = BrainOutput(visual: visual, isSuspended: !suspendReasons.isEmpty, isWorkMode: workMode,
                             bubble: showsBubble ? bubble?.kind : nil)
    }
}
