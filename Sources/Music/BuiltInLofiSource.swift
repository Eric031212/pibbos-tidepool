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
        plan = RadioPlan(library: library, random: Self.random)
        isPlaying = true
        continuation.yield(.started)
        playNext()
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
            self.continuation.yield(.paused)
        }
        RunLoop.main.add(timer, forMode: .common)
        fadeTimer = timer
    }

    private func playNext() {
        guard var plan else { return }
        let (theme, track) = plan.next(random: Self.random)
        self.plan = plan
        guard let player = try? AVAudioPlayer(contentsOf: track.url) else { return }
        player.delegate = self
        player.volume = 0
        player.prepareToPlay()
        player.play()
        player.setVolume(volume, fadeDuration: fadeInDuration)
        self.player = player
        beat = BeatGrid(bpm: track.bpm, offset: track.offset).map {
            BeatSync(grid: $0, trackStart: CACurrentMediaTime() - player.currentTime)
        }
        nowPlaying = "\(theme) - \(track.title)"
        continuation.yield(.trackChanged)
    }

    func audioPlayerDidFinishPlaying(_ finished: AVAudioPlayer, successfully flag: Bool) {
        guard isPlaying, finished === player else { return }
        playNext()
    }

    deinit {
        continuation.finish()
    }
}
