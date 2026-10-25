import AppKit
import Brain
import Content
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
    }

    private var brain: Brain
    private let pack: SkinPack
    private let renderer: SpriteRenderer
    private let bubbleRenderer: BubbleRenderer
    private let panel: PetPanel
    private let bubblePanel: BubblePanel
    private let menuPanel: PixelMenuPanel
    private let marqueePanel: MarqueePanel
    private let brainConfig: BrainConfig
    private let demo: Bool

    private let idleMonitor = IdleMonitor()
    private let sessionMonitor = SessionMonitor()
    private let fullscreenProbe = FullscreenProbe()
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
        panel = PetPanel(layers: [renderer.bottleLayer, renderer.gardenLayer, renderer.rippleLayer, renderer.layer, renderer.starLayer],
                         size: NSSize(width: petX + cell, height: cell),
                         petRect: NSRect(x: petX, y: 0, width: cell, height: cell))
        bubblePanel = BubblePanel(scale: Self.uiScale)
        menuPanel = PixelMenuPanel(renderer: bubbleRenderer, scale: Self.uiScale)
        marqueePanel = MarqueePanel(renderer: bubbleRenderer, scale: Self.uiScale)

        worldMonitor = WorldMonitor(zoneTab: resources.zoneTab)
        lofi = BuiltInLofiSource(directory: resources.music)
        musicSources = [AppleMusicWatcher(), lofi]
        brainConfig = demo ? .demo : BrainConfig()
        let savedBottle = UserDefaults.standard.object(forKey: Self.nextBottleKey) as? Date
        let forcedBottle = CommandLine.arguments.contains("--bottle") ? Date().addingTimeInterval(3) : nil
        brain = Brain(config: brainConfig, now: Date(), nextBottle: forcedBottle ?? (demo ? nil : savedBottle))

        if UserDefaults.standard.object(forKey: Self.firstLaunchKey) == nil {
            UserDefaults.standard.set(Date(), forKey: Self.firstLaunchKey)
        }
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

        idleMonitor.onSample = { [weak self] seconds in self?.send(.userIdle(seconds: seconds)) }
        sessionMonitor.onEvent = { [weak self] event in self?.send(event) }
        fullscreenProbe.onChange = { [weak self] isFullscreen in
            self?.send(isFullscreen ? .suspended(.fullscreen) : .resumed(.fullscreen))
        }
        worldMonitor.onChange = { [weak self] context in self?.worldChanged(context) }

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

        sessionMonitor.start()
        if SessionMonitor.isLockedNow { send(.suspended(.locked)) }
        fullscreenProbe.start()
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
        }
        send(.musicChanged(source: source.id, playing: event != .paused))
        if source === lofi, event == .trackChanged {
            send(.builtInTrackStarted)
            if shownBubble == .nowPlaying { showNowPlaying() }  // new title
        }
    }

    private func worldChanged(_ context: WorldContext) {
        renderer.outfit = context.holiday?.rawValue
        renderer.lighting = context.timeOfDay.rawValue
        renderer.moonlight = context.moonlight
        send(.clearNightChanged(Self.forcedStars || context.isClearNight))
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
        starWasFalling = output.shootingStar
        if !demo, UserDefaults.standard.object(forKey: Self.nextBottleKey) as? Date != brain.nextBottle {
            UserDefaults.standard.set(brain.nextBottle, forKey: Self.nextBottleKey)
        }

        updateBubble(output.isSuspended ? nil : output.bubble)
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
        case .note, .wish:
            let text: String
            if case .note(let pick) = bubble { text = Strings.bottleNote(pick: pick) } else { text = Strings.Bubble.wish }
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

    // MARK: - Playing

    private func splashed(atX x: CGFloat) {
        guard !brain.output.isWorkMode else { return }
        if brain.output.bottle, bottleHitRange.contains(x) {
            send(.bottleClicked)  // Pibbo fishes it out and reads the note
            return
        }
        renderer.playRipple(atX: x, within: panel.frame.width)
        send(.splashed)
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
        if brain.output.shootingStar {
            send(.wished)  // right after a shooting star, a click is a wish
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
        items.append(.init(title: Strings.Menu.workMode) { [weak self] in self?.send(.workModeEntered) })
        items.append(.init(title: Strings.Menu.quit) { NSApp.terminate(nil) })
        let anchor = bubbleAnchor()
        menuPanel.open(items, anchorX: anchor.x, bottomY: anchor.y)
    }
}
