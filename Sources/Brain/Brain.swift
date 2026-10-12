import Foundation

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

    /// Starts in the launch flow: `peek` for a few seconds, then `chill`.
    public init(config: BrainConfig = BrainConfig(), now: Date,
                random: @escaping (ClosedRange<Double>) -> Double = { Double.random(in: $0) }) {
        self.config = config
        self.random = random
        presence = .peek(until: now.addingTimeInterval(config.launchPeek))
        lastInteraction = now
        output = BrainOutput(visual: .state(.peek), isSuspended: false, isWorkMode: false)
        refreshOutput()
    }

    /// When the platform should deliver `.timerFired`; `nil` means no timer.
    /// Always `nil` while suspended, so nothing runs in the background.
    public var nextDeadline: Date? {
        guard suspendReasons.isEmpty else { return nil }
        var candidates = Array(pendingStops.values)
        switch presence {
        case .hidden:
            if let nextAppearance, !workMode { candidates.append(nextAppearance) }
        case .peek(let until), .appearance(_, let until):
            candidates.append(until)
        case .chill(let hideAt):
            candidates.append(hideAt)
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
            case .hidden: presence = .peek(until: now.addingTimeInterval(config.hoverPeek))
            case .peek: break
            case .chill, .appearance: presence = .chill(hideAt: now.addingTimeInterval(config.hideAfterNoInteraction))
            }

        case .hoverEnded:
            guard hovering else { break }
            hovering = false
            lastInteraction = now
            if case .chill = presence {
                presence = .chill(hideAt: now.addingTimeInterval(config.hideAfterNoInteraction))
            }

        case .clicked:
            workMode = false
            isUserAway = false
            lastInteraction = now
            presence = .chill(hideAt: now.addingTimeInterval(config.hideAfterNoInteraction))

        case .workModeEntered:
            workMode = true
            hovering = false
            presence = .hidden
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
            } else if playingSources.contains(source) {
                pendingStops[source] = now.addingTimeInterval(config.musicStopDebounce)
            }

        case .suspended(let reason):
            if suspendReasons.isEmpty {
                hovering = false
                presence = .hidden
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

        case .timerFired:
            break  // advance(to:) above already did the work
        }

        refreshOutput()
    }

    // MARK: - Private

    private var canAppearOnHisOwn: Bool {
        !workMode && suspendReasons.isEmpty && playingSources.isEmpty && !isUserAway
    }

    private mutating func becomeHidden(at now: Date) {
        presence = .hidden
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

        // A few passes cover chains such as peek → chill → hidden after a long gap.
        for _ in 0..<4 {
            switch presence {
            case .peek(let until) where until <= now:
                presence = .chill(hideAt: lastInteraction.addingTimeInterval(config.hideAfterNoInteraction))
            case .chill(let hideAt) where hideAt <= now:
                if hovering {
                    presence = .chill(hideAt: now.addingTimeInterval(config.hideAfterNoInteraction))
                } else {
                    becomeHidden(at: hideAt)
                }
            case .appearance(_, let until) where until <= now:
                becomeHidden(at: until)
            case .hidden:
                guard let due = nextAppearance, due <= now, !workMode else { return }
                let isStale = now.timeIntervalSince(due) > config.actionDuration.upperBound
                if canAppearOnHisOwn && !isStale {
                    presence = .appearance(action: pickAction(),
                                           until: now.addingTimeInterval(random(config.actionDuration)))
                } else {
                    nextAppearance = now.addingTimeInterval(random(config.randomAppearanceInterval))
                }
            default:
                return
            }
        }
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
            case .chill: visual = .state(.chill)
            case .appearance(let action, _): visual = action.map(PetVisual.action) ?? .state(.chill)
            }
        }
        output = BrainOutput(visual: visual, isSuspended: !suspendReasons.isEmpty, isWorkMode: workMode)
    }
}
