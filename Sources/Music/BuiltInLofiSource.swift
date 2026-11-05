import AVFoundation
import Brain
import Content
import QuartzCore

/// The beats of the track playing now, anchored to `CACurrentMediaTime()`.
struct BeatSync {
    let grid: BeatGrid
    /// Media time at which the track was at 0 s.
    let trackStart: CFTimeInterval
}

/// The built-in lofi radio (CLAUDE.md Section 9). Never starts on its own:
/// only from the menu or the `Music Time? 🎧` bubble. The listener never
/// picks songs: every start is a random theme in shuffled order
/// (`RadioPlan`), and stopping fades out instead of cutting off.
final class BuiltInLofiSource: NSObject, MusicSource, AVAudioPlayerDelegate {
    let id = Brain.builtInSource
    let events: AsyncStream<MusicEvent>

    private let continuation: AsyncStream<MusicEvent>.Continuation
    private let library: MusicLibrary
    private var plan: RadioPlan?
    private var player: AVAudioPlayer?
    private var fadeTimer: Timer?

    private let volume: Float = 0.5
    private let fadeInDuration: TimeInterval = 1.0

    /// "theme - track" of what is playing, for the scrolling bubble.
    private(set) var nowPlaying: String?
    /// Beats of the current track (nil without a beat map or when stopped).
    private(set) var beat: BeatSync?
    /// The playing theme's skin prop (nil when stopped or the theme has none).
    private(set) var prop: String?
    /// The playing theme's toy (e.g. "game"), nil when stopped or none.
    private(set) var toy: String?
    /// `--theme <title>`: start the radio with that theme (testing).
    private static let forcedTheme: String? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--theme"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()

    var isAvailable: Bool { !library.isEmpty }
    /// True while playing, false once a fade-out has begun.
    private(set) var isPlaying = false

    init(directory: URL?) {
        (events, continuation) = AsyncStream.makeStream(of: MusicEvent.self)
        library = directory.map(MusicLibrary.load) ?? MusicLibrary(themes: [])
        super.init()
    }

    private static func random(_ n: Int) -> Int { Int.random(in: 0..<n) }

    /// Starts a fresh random theme, or recovers from a fade that is still running.
    func play() {
        guard isAvailable, !isPlaying else { return }
        if fadeTimer != nil, let player {
            // Changed our mind mid-fade: bring the same song back up.
            fadeTimer?.invalidate()
            fadeTimer = nil
            player.setVolume(volume, fadeDuration: 0.4)
            isPlaying = true
            continuation.yield(.started)
            return
        }
        plan = RadioPlan(library: library, random: Self.random, startingWith: Self.forcedTheme)
        // Only say "started" once a track really plays: never headphones without sound.
        guard startNextPlayable() else {
            plan = nil
            return
        }
        isPlaying = true
        continuation.yield(.started)
        continuation.yield(.trackChanged)
    }

    /// Fades to silence over `duration`, then pauses.
    func fadeOut(duration: TimeInterval) {
        guard isPlaying, let player else { return }
        isPlaying = false
        player.setVolume(0, fadeDuration: duration)
        let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.fadeTimer = nil
            self.player?.stop()
            self.player = nil
            self.nowPlaying = nil
            self.beat = nil
            self.prop = nil
            self.toy = nil
            self.continuation.yield(.paused)
        }
        RunLoop.main.add(timer, forMode: .common)
        fadeTimer = timer
    }

    /// Starts the next track that actually plays, skipping any that fail to
    /// load or start (at most one pass over the whole library). False if none do.
    private func startNextPlayable() -> Bool {
        guard var plan else { return false }
        let attempts = library.themes.reduce(0) { $0 + $1.tracks.count }
        for _ in 0..<attempts {
            let (theme, track) = plan.next(random: Self.random)
            self.plan = plan
            guard let player = try? AVAudioPlayer(contentsOf: track.url) else { continue }
            player.delegate = self
            player.volume = 0
            guard player.prepareToPlay(), player.play() else { continue }
            player.setVolume(volume, fadeDuration: fadeInDuration)
            self.player = player
            beat = BeatGrid(bpm: track.bpm, offset: track.offset).map {
                BeatSync(grid: $0, trackStart: CACurrentMediaTime() - player.currentTime)
            }
            nowPlaying = "\(theme) - \(track.title)"
            prop = plan.theme.prop
            toy = plan.theme.toy
            return true
        }
        return false
    }

    /// Nothing plays any more: back to silence, with nothing left on screen.
    private func giveUp() {
        isPlaying = false
        player?.stop()
        player = nil
        plan = nil
        nowPlaying = nil
        beat = nil
        prop = nil
        toy = nil
        continuation.yield(.paused)
    }

    private func playNext() {
        if startNextPlayable() { continuation.yield(.trackChanged) } else { giveUp() }
    }

    func audioPlayerDidFinishPlaying(_ finished: AVAudioPlayer, successfully flag: Bool) {
        guard isPlaying, finished === player else { return }
        playNext()
    }

    /// A track that breaks mid-way: move on to the next one.
    func audioPlayerDecodeErrorDidOccur(_ broken: AVAudioPlayer, error: Error?) {
        guard isPlaying, broken === player else { return }
        playNext()
    }

    deinit {
        continuation.finish()
    }
}
