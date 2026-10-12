import AppKit
import Brain
import Content
import Strings

/// Wires everything together: system signals → Brain → window + renderer.
/// Brain decides; this class only translates. It keeps exactly one timer,
/// for `brain.nextDeadline`, and none at all while Pibbo is suspended.
final class PetController {
    private var brain: Brain
    private let pack: SkinPack
    private let renderer: SpriteRenderer
    private let panel: PetPanel

    private let idleMonitor = IdleMonitor()
    private let sessionMonitor = SessionMonitor()
    private let fullscreenProbe = FullscreenProbe()
    private let musicSources: [MusicSource] = [AppleMusicWatcher()]
    private var musicTasks: [Task<Void, Never>] = []

    private var deadlineTimer: Timer?
    private var screenToken: NSObjectProtocol?

    /// Integer scale for the 16×16 sprite: 4× = 64 pt (spike 3/4: crisp).
    private static let scale = 4

    init(pack: SkinPack) throws {
        self.pack = pack
        renderer = try SpriteRenderer(pack: pack, scale: Self.scale)
        panel = PetPanel(contentLayer: renderer.layer, size: renderer.pointSize)
        brain = Brain(now: Date())
    }

    func start() {
        panel.petView.onHoverBegan = { [weak self] in self?.send(.hoverBegan) }
        panel.petView.onHoverEnded = { [weak self] in self?.send(.hoverEnded) }
        panel.petView.onClick = { [weak self] event in self?.clicked(event) }

        idleMonitor.onSample = { [weak self] seconds in self?.send(.userIdle(seconds: seconds)) }
        sessionMonitor.onEvent = { [weak self] event in self?.send(event) }
        fullscreenProbe.onChange = { [weak self] isFullscreen in
            self?.send(isFullscreen ? .suspended(.fullscreen) : .resumed(.fullscreen))
        }

        for source in musicSources {
            musicTasks.append(Task { @MainActor [weak self] in
                for await event in source.events {
                    self?.send(.musicChanged(source: source.id, playing: event != .paused))
                }
            })
        }

        screenToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.panel.moveToCorner() }

        send(.availableActionsChanged(pack.availableActions))
        panel.moveToCorner()
        apply()

        sessionMonitor.start()
        if SessionMonitor.isLockedNow { send(.suspended(.locked)) }
        fullscreenProbe.start()
        if !brain.output.isSuspended { idleMonitor.start() }
    }

    // MARK: - Brain

    private func send(_ event: BrainEvent) {
        brain.handle(event, at: Date())
        apply()
    }

    private func apply() {
        let output = brain.output

        if output.isSuspended {
            renderer.pause()
            panel.orderOut(nil)
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

        scheduleDeadline()
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

    // MARK: - Click and menu

    private func clicked(_ event: NSEvent) {
        if brain.output.isWorkMode {
            send(.clicked)  // a click ends work mode; no menu
            return
        }
        send(.clicked)

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(menuItem(Strings.Menu.workMode) { [weak self] in self?.send(.workModeEntered) })
        menu.addItem(menuItem(Strings.Menu.quit) { NSApp.terminate(nil) })
        let point = panel.petView.convert(event.locationInWindow, from: nil)
        menu.popUp(positioning: nil, at: point, in: panel.petView)
    }

    private func menuItem(_ title: String, action: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
        let target = MenuAction(action)
        item.target = target
        item.representedObject = target  // keep the target alive with the item
        return item
    }
}

private final class MenuAction: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func run() { action() }
}
