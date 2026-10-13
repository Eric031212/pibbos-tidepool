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

    init(resources: Resources, demo: Bool) throws {
        self.demo = demo
        pack = try SkinPack.load(from: resources.skin)
        renderer = try SpriteRenderer(pack: pack, scale: Self.scale)
        bubbleRenderer = try BubbleRenderer(directory: resources.ui)

        // Flower on the left, Pibbo on the right.
        let cell = renderer.pointSize
        let petX = renderer.hasGarden ? cell : 0
        renderer.layer.frame.origin.x = petX
        panel = PetPanel(layers: [renderer.gardenLayer, renderer.layer],
                         size: NSSize(width: petX + cell, height: cell),
                         petRect: NSRect(x: petX, y: 0, width: cell, height: cell))
        bubblePanel = BubblePanel(scale: Self.uiScale)
        menuPanel = PixelMenuPanel(renderer: bubbleRenderer, scale: Self.uiScale)

        worldMonitor = WorldMonitor(zoneTab: resources.zoneTab)
        lofi = BuiltInLofiSource(directory: resources.music)
        musicSources = [AppleMusicWatcher(), lofi]
        brain = Brain(config: demo ? .demo : BrainConfig(), now: Date())

        if UserDefaults.standard.object(forKey: Self.firstLaunchKey) == nil {
            UserDefaults.standard.set(Date(), forKey: Self.firstLaunchKey)
        }
    }

    func start() {
        panel.petView.onHoverBegan = { [weak self] in self?.send(.hoverBegan) }
        panel.petView.onHoverEnded = { [weak self] in self?.send(.hoverEnded) }
        panel.petView.onClick = { [weak self] event in self?.clicked(event) }
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
                    self?.send(.musicChanged(source: source.id, playing: event != .paused))
                }
            })
        }

        activationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.menuPanel.close() }

        screenToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.panel.moveToCorner()
            self?.apply()
        }

        send(.builtInMusicAvailable(lofi.isAvailable))
        worldChanged(worldMonitor.context)
        panel.moveToCorner()
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

    private func worldChanged(_ context: WorldContext) {
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
        renderer.gardenLayer.isHidden = !pibboIsOut
        renderer.showGarden(stage: gardenStage())

        updateBubble(output.isSuspended ? nil : output.bubble)
        scheduleDeadline()
    }

    /// Days since the first launch; in `--demo`, every 30 seconds counts as a day.
    private func gardenStage() -> Int {
        let stages = pack.manifest.garden?.stages ?? 0
        let days: Double
        if demo {
            days = Date().timeIntervalSince(launchDate) / 30
        } else {
            let first = UserDefaults.standard.object(forKey: Self.firstLaunchKey) as? Date ?? Date()
            days = Date().timeIntervalSince(first) / 86_400
        }
        return Garden.stage(daysSinceFirstLaunch: days, stageCount: stages)
    }

    private func updateBubble(_ bubble: Bubble?) {
        guard bubble != shownBubble else { return }
        shownBubble = bubble
        guard let bubble else {
            bubblePanel.orderOut(nil)
            return
        }
        let text: String
        switch bubble {
        case .musicInvitation: text = Strings.Bubble.musicInvitation
        }
        guard let image = bubbleRenderer.image(for: text) else { return }
        let anchor = bubbleAnchor()
        bubblePanel.show(image, tailInsetFromRight: bubbleRenderer.tailInsetFromRight,
                         anchorX: anchor.x, bottomY: anchor.y)
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
        send(.bubbleClicked)
        lofi.play()
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
        send(.clicked)

        var items: [PixelMenuPanel.Item] = []
        if lofi.isAvailable {
            let title = lofi.isPlaying ? Strings.Menu.stopMusic : Strings.Menu.music
            items.append(.init(title: title) { [weak self] in self?.lofi.toggle() })
        }
        items.append(.init(title: Strings.Menu.workMode) { [weak self] in self?.send(.workModeEntered) })
        items.append(.init(title: Strings.Menu.quit) { NSApp.terminate(nil) })
        let anchor = bubbleAnchor()
        menuPanel.open(items, anchorX: anchor.x, bottomY: anchor.y)
    }
}
