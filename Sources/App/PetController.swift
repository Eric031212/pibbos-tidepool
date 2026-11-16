import AppKit
import Brain
import Content
import Games
import Strings
import World

/// Wires everything together: system signals → Brain → windows + renderer.
/// Brain decides; this class only translates. It keeps exactly one timer,
/// for `brain.nextDeadline`, and none at all while Pibbo is suspended.
final class PetController {
    struct Resources {
        let skin: URL
        let ui: URL
        let music: URL?
        let zoneTab: URL?
        let games: URL?
        let sounds: URL?
    }

    private var brain: Brain
    private let pack: SkinPack
    private let renderer: SpriteRenderer
    private let bubbleRenderer: BubbleRenderer
    private let panel: PetPanel
    private let bubblePanel: BubblePanel
    private let menuPanel: PixelMenuPanel
    private let marqueePanel: MarqueePanel
    private let games: GameController
    private let tide: TideSounds
    private var callActive = false
    private let brainConfig: BrainConfig
    private let demo: Bool

    private let idleMonitor = IdleMonitor()
    private let sessionMonitor = SessionMonitor()
    private let fullscreenProbe = FullscreenProbe()
    private let callMonitor = CallMonitor()
    private let worldMonitor: WorldMonitor
    private let lofi: BuiltInLofiSource
    private let musicSources: [MusicSource]
    private var musicTasks: [Task<Void, Never>] = []

    private var deadlineTimer: Timer?
    private var screenToken: NSObjectProtocol?
    private var activationToken: NSObjectProtocol?
    private var shownBubble: Bubble?
    private let launchDate = Date()

    /// Integer scale for the 16×16 sprites: 4× = 64 pt (spikes 3/4: crisp).
    private static let scale = 4
    /// Bubbles and the menu use half of Pibbo's pixel size: readable, but small.
    private static let uiScale = 2
    private static let firstLaunchKey = "firstLaunchDate"
    private static let nextBottleKey = "nextBottle"
    /// `--stars`: treat it as a clear night, so shooting stars fall (with `--demo`, every 15–25 s).
    private static let forcedStars = CommandLine.arguments.contains("--stars")
    private var starWasFalling = false
    private var shownVisitor: String?
    /// The seagull's story; saved, except in `--demo` (a demo doesn't spend the real gift).
    private var seagullVisits = 0
    private var hasGift = false
    private static let seagullVisitsKey = "seagullVisits"
    private static let hasGiftKey = "seagullGiftBrought"
    /// `--visitor <crab|seagull|fish|friend>`: only that visitor, every few seconds.
    private static let forcedVisitor: String? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--visitor"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()
    private var lastSnow: Date?
    private static let snowLingers: TimeInterval = 2 * 3600
    private var lastWeather: Weather?
    private var rainbowUntil: Date?
    private static let rainbowLasts: TimeInterval = 10 * 60
    /// `--rainbow`: a rainbow right after launch.
    private static let forcedRainbow = CommandLine.arguments.contains("--rainbow")
    /// Greetings (v1.4): what has been said, when you were last here, first launch.
    private var greetingMemory = GreetingMemory()
    private var lastActiveMoment: Date?
    private var isFirstLaunch = false
    /// `--greet <hello|morning|weekend|welcome|night>`: that greeting 3 s after launch.
    private static let forcedGreeting: String? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--greet"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()

    /// `--game <id>`: opens that game 2 s after launch (e.g. `--game shellCatch`).
    private static let forcedGame: String? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--game"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()
    /// Things Pibbo saw lately, newest last: what he dreams of.
    private var memories: [String] = []
    private var recentSplashes: [Date] = []
    /// x range (view points) where a click opens the bottle: its channel.
    private let bottleHitRange: ClosedRange<CGFloat>
    /// `--garden-days <n>` shows the flower and meadow as on day n.
    private static let forcedGardenDays: Double? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--garden-days"), i + 1 < args.count else { return nil }
        return Double(args[i + 1])
    }()

    init(resources: Resources, demo: Bool) throws {
        self.demo = demo
        pack = try SkinPack.load(from: resources.skin)
        renderer = try SpriteRenderer(pack: pack, scale: Self.scale)
        bubbleRenderer = try BubbleRenderer(directory: resources.ui)

        // Meadow, flower, then Pibbo, left to right. The meadow is drawn by
        // the garden layer one cell to its left; the bottle floats under the
        // garden, in the flower's cell.
        let cell = renderer.pointSize
        let gardenX = renderer.hasMeadow ? cell : 0
        let petX = gardenX + (renderer.hasGarden ? cell : 0)
        renderer.gardenLayer.frame.origin.x = gardenX
        renderer.bottleLayer.frame.origin.x = gardenX
        renderer.layer.frame.origin.x = petX
        bottleHitRange = gardenX...(gardenX + cell / 4)
        renderer.starLayer.frame.origin.x = renderer.hasGarden ? gardenX : petX
        panel = PetPanel(layers: [renderer.bottleLayer, renderer.gardenLayer, renderer.visitorLayer, renderer.rippleLayer,
                                  renderer.layer, renderer.starLayer],
                         size: NSSize(width: petX + cell, height: cell),
                         petRect: NSRect(x: petX, y: 0, width: cell, height: cell))
        bubblePanel = BubblePanel(scale: Self.uiScale)
        menuPanel = PixelMenuPanel(renderer: bubbleRenderer, scale: Self.uiScale)
        marqueePanel = MarqueePanel(renderer: bubbleRenderer, scale: Self.uiScale)
        games = GameController(directory: resources.games, text: bubbleRenderer)
        tide = TideSounds(directory: resources.sounds)

        worldMonitor = WorldMonitor(zoneTab: resources.zoneTab)
        lofi = BuiltInLofiSource(directory: resources.music)
        musicSources = [AppleMusicWatcher(), lofi]
        var config = demo ? BrainConfig.demo : BrainConfig()
        if CommandLine.arguments.contains("--dreams") {
            // `--dreams`: falls asleep at the next idle check (~30 s) and dreams every few seconds.
            config.idleBeforeSleep = 5
            config.idleBeforeSleepAtNight = 5
            config.dreamInterval = 6...8
        }
        if Self.forcedVisitor != nil {
            // `--visitor <name>`: that visitor, on every appearance, every few seconds.
            config.visitorChance = 1
            config.hideAfterNoInteraction = 6
            config.randomAppearanceInterval = 4...6
        }
        brainConfig = config
        let savedBottle = UserDefaults.standard.object(forKey: Self.nextBottleKey) as? Date
        let forcedBottle = CommandLine.arguments.contains("--bottle") ? Date().addingTimeInterval(3) : nil
        brain = Brain(config: brainConfig, now: Date(), nextBottle: forcedBottle ?? (demo ? nil : savedBottle))

        if !demo {
            seagullVisits = UserDefaults.standard.integer(forKey: Self.seagullVisitsKey)
            hasGift = UserDefaults.standard.bool(forKey: Self.hasGiftKey)
        }
        renderer.showsGift = hasGift
        if UserDefaults.standard.object(forKey: Self.firstLaunchKey) == nil {
            UserDefaults.standard.set(Date(), forKey: Self.firstLaunchKey)
            isFirstLaunch = true
        }
        let defaults = UserDefaults.standard
        greetingMemory = GreetingMemory(morningDay: defaults.string(forKey: "greet.morningDay"),
                                        welcomeBackDay: defaults.string(forKey: "greet.welcomeBackDay"),
                                        welcomeBacksThatDay: defaults.integer(forKey: "greet.welcomeBacks"),
                                        nightOwlDay: defaults.string(forKey: "greet.nightOwlDay"),
                                        season: defaults.string(forKey: "greet.season"),
                                        milestone: defaults.integer(forKey: "greet.milestone"),
                                        firstSnowWinter: defaults.string(forKey: "greet.firstSnow"))
    }

    func start() {
        panel.petView.onHoverBegan = { [weak self] in self?.send(.hoverBegan) }
        panel.petView.onHoverEnded = { [weak self] in self?.send(.hoverEnded) }
        panel.petView.onClick = { [weak self] event in self?.clicked(event) }
        panel.petView.onDrag = { [weak self] x in self?.dragged(toX: x) }
        panel.petView.onDragEnded = { [weak self] in self?.panel.rememberShorePosition() }
        panel.petView.onRub = { [weak self] in self?.send(.rubbed) }
        panel.petView.onHoldBegan = { [weak self] in self?.send(.holdBegan) }
        panel.petView.onHoldEnded = { [weak self] in self?.send(.holdEnded) }
        panel.petView.onSplash = { [weak self] x in self?.splashed(atX: x) }
        bubblePanel.onClick = { [weak self] in self?.bubbleClicked() }
        games.onOpenChanged = { [weak self] open in self?.send(.gameChanged(open)) }

        idleMonitor.onSample = { [weak self] seconds in
            self?.send(.userIdle(seconds: seconds))
            self?.noticeActivity(idle: seconds)
        }
        sessionMonitor.onEvent = { [weak self] event in self?.send(event) }
        fullscreenProbe.onChange = { [weak self] isFullscreen in
            self?.send(isFullscreen ? .suspended(.fullscreen) : .resumed(.fullscreen))
        }
        worldMonitor.onChange = { [weak self] context in self?.worldChanged(context) }
        callMonitor.onChange = { [weak self] active in
            self?.callActive = active
            self?.send(.callChanged(active))
        }

        for source in musicSources {
            musicTasks.append(Task { @MainActor [weak self] in
                for await event in source.events {
                    self?.musicEvent(event, from: source)
                }
            })
        }

        activationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.menuPanel.close() }

        screenToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.panel.moveToShore()
            self?.followPibbo()
        }

        send(.builtInMusicAvailable(lofi.isAvailable))
        worldChanged(worldMonitor.context)
        panel.moveToShore()
        apply()

        if Self.forcedRainbow { showRainbow(true) }
        // `--tide`: tide sounds from the start (for listening while trying things).
        if CommandLine.arguments.contains("--tide"), tide.isAvailable { tide.start(mix: TideMix.layers(for: worldMonitor.context)) }
        // Launch (at login, most mornings): say hello once the weather is likely in.
        DispatchQueue.main.asyncAfter(deadline: .now() + (Self.forcedGreeting != nil ? 3 : 20)) { [weak self] in
            self?.greetAtLaunch()
        }
        if let id = Self.forcedGame {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self else { return }
                self.games.show(id: id, above: self.panel.frame)
            }
        }
        sessionMonitor.start()
        if SessionMonitor.isLockedNow { send(.suspended(.locked)) }
        fullscreenProbe.start()
        callMonitor.start()
        worldMonitor.start()
        if !brain.output.isSuspended { idleMonitor.start() }
    }

    // MARK: - Brain

    private func send(_ event: BrainEvent) {
        brain.handle(event, at: Date())
        apply()
    }

    private func musicEvent(_ event: MusicEvent, from source: MusicSource) {
        if source === lofi {
            renderer.beat = lofi.beat
            renderer.prop = lofi.prop
            send(.radioToyChanged(lofi.toy))
        }
        if source === lofi, event != .paused { tide.stop() }  // the radio takes over from the tide
        send(.musicChanged(source: source.id, playing: event != .paused))
        if event != .paused { remember("music") }
        if source === lofi, event == .trackChanged {
            send(.builtInTrackStarted)
            if shownBubble == .nowPlaying { showNowPlaying() }  // new title
        }
    }

    private func worldChanged(_ context: WorldContext) {
        renderer.outfit = context.holiday?.rawValue
        renderer.season = context.season.rawValue
        tide.update(mix: TideMix.layers(for: context))
        renderer.lighting = context.timeOfDay.rawValue
        renderer.moonlight = context.moonlight
        renderer.drift = Drift.item(for: context)
        switch context.weather {
        case .rain, .storm: renderer.weatherEffect = "rain"
        case .snow: renderer.weatherEffect = "snow"
        default: renderer.weatherEffect = nil
        }
        // Rain gives way to sun or clouds by day: a rainbow for a little while.
        let wet: Set<Weather?> = [.rain, .storm]
        if wet.contains(context.weather) {
            showRainbow(false)
        } else if wet.contains(lastWeather), context.weather != nil, context.timeOfDay != .night {
            showRainbow(true)
        }
        let userIsHere = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!) < 300
        if context.weather == .snow, lastWeather != nil, lastWeather != .snow, !brain.output.isSuspended, userIsHere {
            let (greeting, memory) = Greetings.snowStarted(at: Date(), memory: greetingMemory, calendar: .current)
            remember(memory)
            if let greeting { send(.greeted(greeting)) }
        }
        lastWeather = context.weather
        // Snow stays on the rocks for a while after it stops falling.
        if context.weather == .snow { lastSnow = Date() }
        renderer.snowCovered = lastSnow.map { Date().timeIntervalSince($0) < Self.snowLingers } ?? false
        send(.clearNightChanged(Self.forcedStars || context.isClearNight))
        let drawn = pack.manifest.visitors ?? [:]
        let welcome = Self.forcedVisitor.map { [$0] } ?? Visitors.candidates(for: context)
        send(.visitorsChanged(welcome.filter { drawn[$0] != nil }, durations: drawn.mapValues(\.duration)))
        let provided = Set(pack.availableActions)
        let actions = ActionRules.actions(for: context).filter(provided.contains)
        brain.handle(.timeOfDayChanged(context.timeOfDay), at: Date())
        send(.availableActionsChanged(actions))
    }

    private func apply() {
        let output = brain.output

        if output.isSuspended {
            renderer.pause()
            panel.orderOut(nil)
            menuPanel.close()
            marqueePanel.hide()
            games.close()  // fullscreen, lock or sleep: the game goes away with everything else
            idleMonitor.stop()
        } else {
            renderer.resume()
            panel.orderFrontRegardless()
            idleMonitor.start()
        }

        switch output.visual {
        case .state(let state): renderer.show(state.rawValue)
        case .action(let name): renderer.show(name)
        case .submerged: renderer.show("submerged")
        }

        // The flower only shows while Pibbo shows his face.
        let pibboIsOut = output.visual != .state(.hidden) && output.visual != .submerged
        renderer.setGardenVisible(pibboIsOut)
        renderer.showGarden(stage: Garden.stage(daysSinceFirstLaunch: gardenDays(), stageCount: pack.manifest.garden?.stages ?? 0))
        renderer.showMeadow(stage: Garden.meadowStage(daysSinceFirstLaunch: gardenDays(), stageCount: pack.manifest.meadow?.stages ?? 0))
        renderer.showBottle(output.bottle && !output.isSuspended)
        if output.shootingStar && !starWasFalling { renderer.playShootingStar() }
        // Under water (Dive time, a call) or suspended: nothing left playing on screen.
        if output.isSuspended || output.visual == .submerged { renderer.stopEffects() }
        if let visitor = output.visitor, visitor != shownVisitor { playVisit(visitor) }
        shownVisitor = output.visitor
        starWasFalling = output.shootingStar
        if !demo, UserDefaults.standard.object(forKey: Self.nextBottleKey) as? Date != brain.nextBottle {
            UserDefaults.standard.set(brain.nextBottle, forKey: Self.nextBottleKey)
        }

        updateBubble(output.isSuspended ? nil : output.bubble)
        tide.hold(output.isSuspended || callActive)
        scheduleDeadline()
    }

    /// Days since the first launch; in `--demo`, every 30 seconds counts as a
    /// day; `--garden-days <n>` pins it.
    private func gardenDays() -> Double {
        if let forced = Self.forcedGardenDays { return forced }
        if demo { return Date().timeIntervalSince(launchDate) / 30 }
        let first = UserDefaults.standard.object(forKey: Self.firstLaunchKey) as? Date ?? Date()
        return Date().timeIntervalSince(first) / 86_400
    }

    private func updateBubble(_ bubble: Bubble?) {
        guard bubble != shownBubble else { return }
        shownBubble = bubble
        bubblePanel.orderOut(nil)
        marqueePanel.hide()
        switch bubble {
        case nil:
            break
        case .musicInvitation:
            guard let image = bubbleRenderer.image(for: Strings.Bubble.musicInvitation) else { return }
            let anchor = bubbleAnchor()
            bubblePanel.show(image, tailInsetFromRight: bubbleRenderer.tailInsetFromRight,
                             anchorX: anchor.x, bottomY: anchor.y)
        case .nowPlaying:
            showNowPlaying()
        case .note, .wish, .dream, .gg, .greeting:
            let text: String
            switch bubble {
            case .greeting(let greeting): text = greetingText(greeting)
            case .note(let pick): text = Strings.bottleNote(pick: pick)
            case .dream(let pick): text = dreamText(pick: pick) ?? Strings.dreams["shell"]!
            case .gg: text = lofi.toy == "piano" ? Strings.Bubble.taDa : Strings.Bubble.gg  // a tune ends with a bow
            default: text = Strings.Bubble.wish
            }
            guard let image = bubbleRenderer.image(for: text) else { return }
            let anchor = bubbleAnchor()
            bubblePanel.show(image, tailInsetFromRight: bubbleRenderer.tailInsetFromRight,
                             anchorX: anchor.x, bottomY: anchor.y)
        }
    }

    /// The now-playing bubble spans the tide pool, tail over Pibbo's head.
    private func showNowPlaying() {
        guard let text = lofi.nowPlaying else { return }
        let pool = panel.frame
        marqueePanel.show(text, pool: pool, tailX: pool.maxX - renderer.pointSize / 2,
                          bottomY: pool.maxY - CGFloat(Self.scale) * 2)
    }

    // MARK: - Rainbow and dreams

    private func showRainbow(_ visible: Bool) {
        renderer.rainbowVisible = visible
        guard visible else {
            rainbowUntil = nil
            return
        }
        let until = Date().addingTimeInterval(Self.rainbowLasts)
        rainbowUntil = until
        send(.rainbowAppeared)
        // One timer, only after rain: the rainbow fades after a while.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.rainbowLasts) { [weak self] in
            guard let self, self.rainbowUntil == until else { return }
            self.showRainbow(false)
        }
    }

    /// Something worth dreaming of tonight.
    private func remember(_ memory: String) {
        memories.removeAll { $0 == memory }
        memories = Array((memories + [memory]).suffix(6))
    }

    private func dreamText(pick: Double) -> String? {
        let pool = memories.isEmpty ? Strings.everydayDreams : memories
        let memory = pool[min(Int(pick * Double(pool.count)), pool.count - 1)]
        return Strings.dreams[memory]
    }

    // MARK: - Visitors

    private func playVisit(_ visitor: String) {
        remember(visitor)
        guard visitor == "seagull" else {
            renderer.playVisitor(visitor)
            return
        }
        let visit = SeagullGift.visit(seagullVisitsSoFar: seagullVisits, hasGift: hasGift)
        renderer.playVisitor(visit)
        seagullVisits += 1
        if !demo { UserDefaults.standard.set(seagullVisits, forKey: Self.seagullVisitsKey) }
        guard visit == "seagullGift", let length = pack.manifest.visitors?[visit]?.duration else { return }
        // Once it has flown off, the feather it set down stays on the rock.
        DispatchQueue.main.asyncAfter(deadline: .now() + length) { [weak self] in
            guard let self else { return }
            self.hasGift = true
            self.renderer.showsGift = true
            if !self.demo { UserDefaults.standard.set(true, forKey: Self.hasGiftKey) }
        }
    }

    // MARK: - Playing

    private func splashed(atX x: CGFloat) {
        guard !brain.output.isWorkMode else { return }
        // The secret: three splashes in a row, quickly, and he flips.
        let now = Date()
        recentSplashes = recentSplashes.filter { now.timeIntervalSince($0) < 1.2 } + [now]
        if brain.output.bottle, bottleHitRange.contains(x) {
            send(.bottleClicked)  // Pibbo fishes it out and reads the note
            remember("bottle")
            return
        }
        renderer.playRipple(atX: x, within: panel.frame.width)
        if recentSplashes.count >= 3 {
            recentSplashes = []
            send(.splashCombo)
        } else {
            send(.splashed)
        }
    }

    // MARK: - Dragging

    private func dragged(toX x: CGFloat) {
        menuPanel.close()
        panel.slide(toX: x)
        followPibbo()
    }

    /// Moves whatever bubble is up along with Pibbo.
    private func followPibbo() {
        let current = shownBubble
        shownBubble = nil
        updateBubble(current)
    }

    /// Stops the built-in radio gently: the volume fades while Pibbo takes
    /// his headphones off.
    private func stopRadio() {
        let duration = brainConfig.unplugDuration
        send(.musicFadingOut(source: lofi.id, duration: duration))
        lofi.fadeOut(duration: duration)
    }

    /// Where bubbles and the menu point: just right of Pibbo's head, with the
    /// tail tip touching it.
    private func bubbleAnchor() -> NSPoint {
        let pet = panel.frame
        return NSPoint(x: pet.maxX - renderer.pointSize / 4, y: pet.maxY - CGFloat(Self.scale) * 2)
    }

    private func scheduleDeadline() {
        deadlineTimer?.invalidate()
        deadlineTimer = nil
        guard let deadline = brain.nextDeadline else { return }
        let interval = max(0, deadline.timeIntervalSinceNow)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in self?.send(.timerFired) }
        timer.tolerance = min(5, max(0.1, interval * 0.1))
        RunLoop.main.add(timer, forMode: .common)
        deadlineTimer = timer
    }

    // MARK: - Click, bubble and menu

    private func bubbleClicked() {
        let wasInvitation = shownBubble == .musicInvitation
        send(.bubbleClicked)
        if wasInvitation { lofi.play() }
    }

    private func clicked(_ event: NSEvent) {
        if brain.output.isWorkMode {
            send(.clicked)  // a click ends work mode; no menu
            return
        }
        if menuPanel.isOpen {
            menuPanel.close()  // a second click closes the menu
            return
        }
        if games.isOpen {
            games.bringToFront()  // a click on Pibbo brings the open game back
            return
        }
        if brain.output.shootingStar {
            send(.wished)  // right after a shooting star, a click is a wish
            remember("star")
            return
        }
        send(.clicked)

        var items: [PixelMenuPanel.Item] = []
        if lofi.isAvailable {
            let title = lofi.isPlaying ? Strings.Menu.stopMusic : Strings.Menu.music
            items.append(.init(title: title) { [weak self] in
                guard let self else { return }
                self.lofi.isPlaying ? self.stopRadio() : self.lofi.play()
            })
        }
        if tide.isAvailable {
            items.append(.init(title: tide.isOn ? Strings.Menu.tideOff : Strings.Menu.tide) { [weak self] in
                guard let self else { return }
                if self.tide.isOn {
                    self.tide.stop()
                } else {
                    if self.lofi.isPlaying { self.stopRadio() }  // one sound at a time
                    self.tide.start(mix: TideMix.layers(for: self.worldMonitor.context))
                }
            })
        }
        if games.isAvailable {
            items.append(.init(title: Strings.Menu.games) { [weak self] in self?.openGameList() })
        }
        items.append(.init(title: Strings.Menu.workMode) { [weak self] in self?.send(.workModeEntered) })
        items.append(.init(title: Strings.Menu.quit) { NSApp.terminate(nil) })
        let anchor = bubbleAnchor()
        menuPanel.open(items, anchorX: anchor.x, bottomY: anchor.y)
    }

    /// `Game time 🎮`: the list of games, in the menu's place.
    private func openGameList() {
        let items = GameCatalog.all.map { entry in
            PixelMenuPanel.Item(title: Strings.Games.titles[entry.id] ?? entry.id) { [weak self] in
                guard let self else { return }
                self.games.show(id: entry.id, above: self.panel.frame)
            }
        }
        let anchor = bubbleAnchor()
        menuPanel.open(items, anchorX: anchor.x, bottomY: anchor.y)
    }

    // MARK: - Greetings

    private func greetAtLaunch() {
        if let forced = Self.forcedGreeting {
            let weather = worldMonitor.context.weather
            let pick: [String: Greeting] = ["hello": .hello, "morning": .morning(weather), "weekend": .weekend(saturday: true),
                                            "welcome": .welcomeBack, "night": .nightOwl,
                                            "season": .newSeason(worldMonitor.context.season), "snow": .firstSnow,
                                            "together": .together(days: 100), "year": .together(days: 365)]
            if let greeting = pick[forced] { send(.greeted(greeting)) }
            return
        }
        let (greeting, memory) = Greetings.onReturn(at: Date(), awayFor: nil, firstLaunch: isFirstLaunch,
                                                    weather: worldMonitor.context.weather, memory: greetingMemory, calendar: .current,
                                                    daysTogether: daysTogether(), season: worldMonitor.context.season)
        remember(memory)
        if let greeting { send(.greeted(greeting)) }
    }

    /// Each idle sample: back after a while away, or up late? (No extra timers.)
    private func noticeActivity(idle seconds: TimeInterval) {
        let now = Date()
        let active = now.addingTimeInterval(-seconds)
        defer { lastActiveMoment = max(lastActiveMoment ?? active, active) }
        guard seconds < 60, Self.forcedGreeting == nil else { return }
        let result: (Greeting?, GreetingMemory)
        if let last = lastActiveMoment, active.timeIntervalSince(last) >= Greetings.welcomeAway {
            result = Greetings.onReturn(at: now, awayFor: active.timeIntervalSince(last), firstLaunch: false,
                                        weather: worldMonitor.context.weather, memory: greetingMemory, calendar: .current,
                                        daysTogether: daysTogether(), season: worldMonitor.context.season)
        } else {
            result = Greetings.nightOwl(at: now, memory: greetingMemory, calendar: .current)
        }
        remember(result.1)
        if let greeting = result.0 { send(.greeted(greeting)) }
    }

    /// Whole days since the first launch (real days, also in `--demo`).
    private func daysTogether() -> Int {
        let first = UserDefaults.standard.object(forKey: Self.firstLaunchKey) as? Date ?? Date()
        return max(0, Int(Date().timeIntervalSince(first) / 86_400))
    }

    private func remember(_ memory: GreetingMemory) {
        guard memory != greetingMemory else { return }
        greetingMemory = memory
        guard !demo else { return }
        let defaults = UserDefaults.standard
        defaults.set(memory.morningDay, forKey: "greet.morningDay")
        defaults.set(memory.welcomeBackDay, forKey: "greet.welcomeBackDay")
        defaults.set(memory.welcomeBacksThatDay, forKey: "greet.welcomeBacks")
        defaults.set(memory.nightOwlDay, forKey: "greet.nightOwlDay")
        defaults.set(memory.season, forKey: "greet.season")
        defaults.set(memory.milestone, forKey: "greet.milestone")
        defaults.set(memory.firstSnowWinter, forKey: "greet.firstSnow")
    }

    private func greetingText(_ greeting: Greeting) -> String {
        switch greeting {
        case .hello: return Strings.Greetings.hello
        case .welcomeBack: return Strings.Greetings.welcomeBack
        case .nightOwl: return Strings.Greetings.nightOwl
        case .firstSnow: return Strings.Greetings.firstSnow
        case .together(let days):
            if days < 365 { return Strings.Greetings.hundredDays }
            let years = days / 365
            return years == 1 ? Strings.Greetings.oneYear : Strings.Greetings.years(years)
        case .newSeason(let season):
            switch season {
            case .spring: return Strings.Greetings.spring
            case .summer: return Strings.Greetings.summer
            case .autumn: return Strings.Greetings.autumn
            case .winter: return Strings.Greetings.winter
            }
        case .weekend(let saturday): return saturday ? Strings.Greetings.saturday : Strings.Greetings.sunday
        case .morning(let weather):
            switch weather {
            case .clear: return Strings.Greetings.morningSunny
            case .cloudy: return Strings.Greetings.morningCloudy
            case .rain, .storm: return Strings.Greetings.morningRainy
            case .snow: return Strings.Greetings.morningSnow
            case nil: return Strings.Greetings.morning
            }
        }
    }
}
