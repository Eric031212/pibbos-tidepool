import AVFoundation

/// Plays the bundled lofi tracks (CLAUDE.md Section 9). Never starts on its
/// own: only from the menu or the `music? 🎧` bubble. One track loops
/// forever; several play in order and wrap around.
final class BuiltInLofiSource: NSObject, MusicSource, AVAudioPlayerDelegate {
    let id = "built-in"
    let events: AsyncStream<MusicEvent>

    private let continuation: AsyncStream<MusicEvent>.Continuation
    private let tracks: [URL]
    private var player: AVAudioPlayer?
    private var trackIndex = 0

    var isAvailable: Bool { !tracks.isEmpty }
    var isPlaying: Bool { player?.isPlaying ?? false }

    init(directory: URL?) {
        (events, continuation) = AsyncStream.makeStream(of: MusicEvent.self)
        let audio: Set<String> = ["caf", "m4a", "mp3", "wav", "aiff"]
        let files = directory.flatMap { try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil) } ?? []
        tracks = files.filter { audio.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        super.init()
    }

    func toggle() {
        isPlaying ? stop() : play()
    }

    func play() {
        guard isAvailable, !isPlaying else { return }
        if player == nil { load(trackIndex) }
        player?.play()
        continuation.yield(.started)
    }

    func stop() {
        guard isPlaying else { return }
        player?.pause()
        continuation.yield(.paused)
    }

    private func load(_ index: Int) {
        guard let player = try? AVAudioPlayer(contentsOf: tracks[index]) else { return }
        player.delegate = self
        player.numberOfLoops = tracks.count == 1 ? -1 : 0
        player.volume = 0.5
        player.prepareToPlay()
        self.player = player
    }

    func audioPlayerDidFinishPlaying(_ finished: AVAudioPlayer, successfully flag: Bool) {
        trackIndex = (trackIndex + 1) % tracks.count
        load(trackIndex)
        player?.play()
        continuation.yield(.trackChanged)
    }

    deinit {
        continuation.finish()
    }
}
