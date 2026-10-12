import Foundation

/// Watches Apple Music through its `com.apple.Music.playerInfo` distributed
/// notification (spike 1: no permission, read only). Limitation: nothing
/// arrives for music that was already playing when Tidepool launched; the
/// state is learned at the next play / pause / skip.
final class AppleMusicWatcher: MusicSource {
    let id = "apple-music"
    let events: AsyncStream<MusicEvent>

    private let continuation: AsyncStream<MusicEvent>.Continuation
    private var token: NSObjectProtocol?
    private var lastTrackID: Int64?

    init() {
        (events, continuation) = AsyncStream.makeStream(of: MusicEvent.self)
        token = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main
        ) { [weak self] note in self?.handle(note.userInfo) }
    }

    private func handle(_ info: [AnyHashable: Any]?) {
        // A 1-key notification (only "Player State") can mean the app quit.
        let isPlaying = info?["Player State"] as? String == "Playing"
        guard isPlaying else {
            lastTrackID = nil
            continuation.yield(.paused)
            return
        }
        let trackID = (info?["PersistentID"] as? NSNumber)?.int64Value
        if let trackID, let lastTrackID, trackID != lastTrackID {
            continuation.yield(.trackChanged)
        }
        lastTrackID = trackID
        continuation.yield(.started)
    }

    deinit {
        if let token { DistributedNotificationCenter.default().removeObserver(token) }
        continuation.finish()
    }
}
