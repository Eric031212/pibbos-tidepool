import AppKit
import Games
import Strings

/// Opens and closes a game (`Game time 🎮`). Everything heavy exists only
/// while a game window is open: the window, its layers, the game art and a
/// 60 fps frame loop. Closing releases all of it, so Tidepool goes back to
/// ~0 % CPU and its usual memory (docs/games-plan.md).
final class GameController {
    /// A game opened (true) or closed (false): Brain plays along.
    var onOpenChanged: ((Bool) -> Void)?

    private let directory: URL?
    private let text: BubbleRenderer
    private var open: OpenGame?

    var isOpen: Bool { open != nil }
    /// The bundled game art exists.
    var isAvailable: Bool { directory != nil && !GameCatalog.all.isEmpty }

    init(directory: URL?, text: BubbleRenderer) {
        self.directory = directory
        self.text = text
        #if DEBUG
        // Debug builds only: drive the open game from a terminal, to measure it
        // without clicking (`open`, `press`, `right`, `stop`, `close`), e.g.
        // swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(.init("io.github.eric031212.pibbostidepool.debug.game"), object: "press", deliverImmediately: true)'
        debugToken = DistributedNotificationCenter.default().addObserver(
            forName: .init("io.github.eric031212.pibbostidepool.debug.game"), object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let command = note.object as? String else { return }
            switch command {
            case "close": self.close()
            case "open": self.show(id: ShellCatch.id, above: NSRect(x: 900, y: 0, width: 192, height: 64))
            default: self.open?.debug(command)
            }
        }
        #endif
    }
    #if DEBUG
    private var debugToken: NSObjectProtocol?
    #endif

    /// Opens a game above the pool (or brings the open one to the front).
    func show(id: String, above pool: NSRect) {
        if let open {
            open.bringToFront()
            return
        }
        guard let directory, let entry = GameCatalog.entry(id: id),
              let art = GameArt(directory: directory, text: text) else { return }
        let game = OpenGame(entry: entry, art: art, best: BestScores.best(for: id))
        game.onClose = { [weak self] in self?.close() }
        open = game
        onOpenChanged?(true)
        game.present(above: pool)
    }

    /// Brings the open game back to the front (a click on Pibbo while it's open).
    func bringToFront() {
        open?.bringToFront()
    }

    /// Closes the game and lets go of everything it held.
    func close() {
        guard let game = open else { return }
        open = nil
        game.tearDown()
        onOpenChanged?(false)
    }
}

/// The one number a game remembers.
enum BestScores {
    private static func key(_ id: String) -> String { "bestScore.\(id)" }

    static func best(for id: String) -> Int {
        UserDefaults.standard.integer(forKey: key(id))
    }

    static func save(_ value: Int, for id: String) {
        guard value > best(for: id) else { return }
        UserDefaults.standard.set(value, forKey: key(id))
    }
}

/// One open game: its window, session, art and frame loop.
private final class OpenGame {
    var onClose: (() -> Void)?

    private let id: String
    private let title: String
    private var session: GameSession
    private let art: GameArt
    private let window: GameWindow
    private let view: GameView
    private var loop: FrameLoop?
    private var lastTick: CFTimeInterval = 0
    private var savedBest: Int
    private var closeHighlighted = false
    private var observers: [NSObjectProtocol] = []
    /// The app that was in front before the game: it gets focus back afterwards.
    private let previousApp: NSRunningApplication?

    init(entry: GameCatalog.Entry, art: GameArt, best: Int) {
        id = entry.id
        title = Strings.Games.titles[entry.id] ?? entry.id
        session = GameSession(game: entry.make { Double.random(in: $0) }, best: best)
        savedBest = best
        self.art = art
        let scale = Self.scale(for: art.chromeSize)
        view = GameView(scale: scale, sheet: art.sheet)
        window = GameWindow(size: view.frame.size)
        window.contentView = view
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front

        view.onClose = { [weak self] in self?.onClose?() }
        view.onCloseHover = { [weak self] hovered in
            self?.closeHighlighted = hovered
            self?.drawChrome()
        }
        view.onPress = { [weak self] in self?.wake() }
        view.chromeLayer.contentsScale = 1
        drawChrome()
        draw()

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            self?.pause()
        })
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.pause()
        })
        observers.append(center.addObserver(forName: NSWindow.didChangeBackingPropertiesNotification, object: window, queue: .main) { [weak self] _ in
            self?.drawChrome()
            self?.draw()
        })
    }

    /// The largest integer scale (4× at most, 2× at least) that fits the screen above the pool.
    private static func scale(for size: CGSize) -> Int {
        guard let visible = NSScreen.screens.first?.visibleFrame else { return 4 }
        for scale in stride(from: 4, through: 2, by: -1) {
            if size.width * CGFloat(scale) <= visible.width - 16 && size.height * CGFloat(scale) <= visible.height - 96 {
                return scale
            }
        }
        return 2
    }

    /// Rises out of the pool: centred over it, just above it, kept on screen.
    func present(above pool: NSRect) {
        let size = window.frame.size
        var origin = NSPoint(x: pool.midX - size.width / 2, y: pool.maxY + 8)
        if let visible = NSScreen.screens.first?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        }
        window.setFrame(NSRect(origin: NSPoint(x: origin.x, y: origin.y - 16), size: size), display: false)
        window.alphaValue = 0
        bringToFront()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            window.animator().setFrame(NSRect(origin: origin, size: size), display: true)
            window.animator().alphaValue = 1
        }
    }

    func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        if !session.isPaused { startLoop() }
    }

    // MARK: - Frame loop

    private func startLoop() {
        guard loop == nil else { return }
        lastTick = CACurrentMediaTime()
        loop = FrameLoop(view: view) { [weak self] in self?.tick() }
    }

    private func stopLoop() {
        loop?.stop()
        loop = nil
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let elapsed = min(now - lastTick, 0.25)
        lastTick = now
        session.receive(view.takeInput())
        if session.advance(by: elapsed) > 0 { draw() }
        if session.best > savedBest {
            savedBest = session.best
            BestScores.save(savedBest, for: id)
        }
    }

    private func draw() {
        view.playLayer.contents = art.render(session, game: id)
    }

    private func drawChrome() {
        view.chromeLayer.contents = art.chrome(title: title, closeHighlighted: closeHighlighted)
    }

    // MARK: - Pause

    /// The window went to the back: stop the loop entirely (0 % CPU while it waits).
    private func pause() {
        guard !session.isPaused else { return }
        stopLoop()
        view.releaseKeys()
        session.pause()
        draw()
    }

    /// A click or space on a paused game wakes it (that press doesn't count as a move).
    private func wake() {
        guard session.isPaused else { return }
        _ = view.takeInput()
        session.resume()
        startLoop()
    }

    #if DEBUG
    func debug(_ command: String) {
        view.debug(command)
        wake()
    }
    #endif

    // MARK: - Closing

    func tearDown() {
        stopLoop()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        view.onClose = nil
        view.onCloseHover = nil
        view.onPress = nil
        view.chromeLayer.contents = nil
        view.playLayer.contents = nil
        let wasKey = window.isKeyWindow
        window.orderOut(nil)
        window.contentView = nil
        // Focus goes back to where it was.
        if wasKey || NSApp.isActive {
            if let previousApp, !previousApp.isTerminated {
                previousApp.activate(options: [])
            } else {
                NSApp.deactivate()
            }
        }
    }
}

/// Calls `tick` once per display frame while it exists: the display's own link
/// on macOS 14+, a 60 fps timer on macOS 13. Only alive while a game plays.
private final class FrameLoop: NSObject {
    private let tick: () -> Void
    private var timer: Timer?
    private var link: AnyObject?

    init(view: NSView, tick: @escaping () -> Void) {
        self.tick = tick
        super.init()
        if #available(macOS 14.0, *) {
            let link = view.displayLink(target: self, selector: #selector(fire))
            link.add(to: .main, forMode: .common)
            self.link = link
        } else {
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.fire() }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    @objc private func fire() { tick() }

    func stop() {
        timer?.invalidate()
        timer = nil
        if #available(macOS 14.0, *) { (link as? CADisplayLink)?.invalidate() }
        link = nil
    }
}
