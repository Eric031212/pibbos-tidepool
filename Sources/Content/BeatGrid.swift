import Foundation

/// The beats of a built-in track, from its beat map (CLAUDE.md Section 9), so
/// Pibbo can nod along. Pure arithmetic; no audio analysis at runtime.
public struct BeatGrid: Equatable, Sendable {
    /// Nodding tempo: the track's bpm folded into `nodRange`. Estimates of
    /// ~120 for half-time lofi are double-time (Section 9), and nodding that
    /// fast would not be chill anyway.
    public let bpm: Double
    /// Track time of the first beat, in seconds.
    public let offset: Double

    public static let nodRange: ClosedRange<Double> = 50...100

    public init?(bpm: Double?, offset: Double?) {
        guard var bpm, bpm.isFinite, bpm > 0 else { return nil }
        while bpm > Self.nodRange.upperBound { bpm /= 2 }
        while bpm < Self.nodRange.lowerBound { bpm *= 2 }
        self.bpm = bpm
        self.offset = max(offset ?? 0, 0)
    }

    public var beatLength: Double { 60 / bpm }

    /// How far into a loop of `beats` beats the music is at `trackTime`, so a
    /// clip started now with this phase lands its first frame on a beat.
    public func phase(at trackTime: Double, beats: Int) -> Double {
        let loop = beatLength * Double(max(beats, 1))
        let elapsed = (trackTime - offset).truncatingRemainder(dividingBy: loop)
        return elapsed < 0 ? elapsed + loop : elapsed
    }
}
