import Foundation

enum MusicEvent: Equatable {
    case started
    case paused
    case trackChanged
}

/// A source of playback events (CLAUDE.md Section 9). Brain does not care
/// where the events come from.
protocol MusicSource: AnyObject {
    /// Stable name used to tell sources apart, e.g. "apple-music".
    var id: String { get }
    var events: AsyncStream<MusicEvent> { get }
}
