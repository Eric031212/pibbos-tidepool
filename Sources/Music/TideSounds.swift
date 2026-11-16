import AVFoundation

/// Tide sounds (v2.0): the pool's ambient loops (Assets/Sounds, made by
/// Tools/generate_tide_sounds.py), mixed by `World.TideMix`. Only plays after
/// the user turns it on; crossfades when the weather or time changes; holds
/// (fades to silence) during calls and while suspended. Players exist only
/// while they are heard, so silence costs nothing.
final class TideSounds {
    private let directory: URL?
    private var players: [String: AVAudioPlayer] = [:]
    private var mix: [String: Float] = [:]
    private var held = false
    /// Bumped on every change, so a delayed clean-up never stops a newer sound.
    private var generation = 0
    private(set) var isOn = false

    /// Overall level, below the radio's.
    private let master: Float = 0.5
    private let crossfade: TimeInterval = 3

    init(directory: URL?) {
        self.directory = directory
    }

    var isAvailable: Bool {
        guard let directory else { return false }
        return FileManager.default.fileExists(atPath: directory.appendingPathComponent("waves.caf").path)
    }

    func start(mix: [String: Float]) {
        isOn = true
        self.mix = mix
        apply(fade: 1.5)
    }

    func stop() {
        guard isOn else { return }
        isOn = false
        silence(fade: 1.6)
    }

    /// The world changed: crossfade to the new mix.
    func update(mix: [String: Float]) {
        guard mix != self.mix else { return }
        self.mix = mix
        if isOn && !held { apply(fade: crossfade) }
    }

    /// A call or suspension: fade out, and back in afterwards.
    func hold(_ hold: Bool) {
        guard hold != held else { return }
        held = hold
        if hold { silence(fade: 1) } else if isOn { apply(fade: 1.5) }
    }

    private func apply(fade: TimeInterval) {
        generation += 1
        for (name, volume) in mix {
            guard let player = player(named: name) else { continue }
            if !player.isPlaying { player.play() }
            player.setVolume(volume * master, fadeDuration: fade)
        }
        let leaving = players.keys.filter { mix[$0] == nil }
        for name in leaving { players[name]?.setVolume(0, fadeDuration: fade) }
        cleanUp(after: fade, keep: Set(mix.keys))
    }

    private func silence(fade: TimeInterval) {
        generation += 1
        players.values.forEach { $0.setVolume(0, fadeDuration: fade) }
        cleanUp(after: fade, keep: [])
    }

    /// Stops and lets go of every player not in `keep` once its fade is done.
    private func cleanUp(after delay: TimeInterval, keep: Set<String>) {
        let ticket = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.2) { [weak self] in
            guard let self, self.generation == ticket else { return }
            for (name, player) in self.players where !keep.contains(name) {
                player.stop()
                self.players[name] = nil
            }
        }
    }

    private func player(named name: String) -> AVAudioPlayer? {
        if let existing = players[name] { return existing }
        guard let url = directory?.appendingPathComponent("\(name).caf"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.numberOfLoops = -1
        player.volume = 0
        player.prepareToPlay()
        players[name] = player
        return player
    }
}
