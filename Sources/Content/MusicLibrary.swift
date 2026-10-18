import Foundation

/// Built-in lofi, grouped into themes (CLAUDE.md Section 9).
///
/// Layout, written by Tools/import_track.py:
///     Music/<theme-slug>/theme.json      {"title": "Pibbo's Raft Days"}
///     Music/<theme-slug>/<track>.caf     audio
///     Music/<theme-slug>/<track>.json    beat map with "title", "bpm", ...
public struct MusicLibrary: Sendable {
    public struct Track: Equatable, Sendable {
        public let title: String
        public let url: URL
        public let bpm: Double?
        /// Seconds from the start of the track to its first beat.
        public var offset: Double? = nil
    }

    public struct Theme: Equatable, Sendable {
        public let title: String
        public let tracks: [Track]
    }

    public let themes: [Theme]

    public init(themes: [Theme]) {
        self.themes = themes.filter { !$0.tracks.isEmpty }
    }

    public var isEmpty: Bool { themes.isEmpty }

    private struct ThemeFile: Decodable { let title: String }
    private struct BeatMap: Decodable {
        let track: String
        let title: String?
        let bpm: Double?
        let offset: Double?
    }

    /// Reads every theme folder; folders without theme.json or tracks are skipped.
    public static func load(from directory: URL) -> MusicLibrary {
        let fm = FileManager.default
        let folders = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        var themes: [Theme] = []
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("theme.json")),
                  let theme = try? JSONDecoder().decode(ThemeFile.self, from: data) else { continue }
            let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            let tracks: [Track] = files
                .filter { $0.pathExtension == "json" && $0.lastPathComponent != "theme.json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .compactMap { url in
                    guard let data = try? Data(contentsOf: url),
                          let map = try? JSONDecoder().decode(BeatMap.self, from: data) else { return nil }
                    let audio = folder.appendingPathComponent(map.track)
                    guard fm.fileExists(atPath: audio.path) else { return nil }
                    return Track(title: map.title ?? audio.deletingPathExtension().lastPathComponent, url: audio, bpm: map.bpm, offset: map.offset)
                }
            themes.append(Theme(title: theme.title, tracks: tracks))
        }
        return MusicLibrary(themes: themes)
    }
}

/// What the built-in radio plays next. The listener never picks songs (that
/// is the point): each session starts with a random theme in a shuffled
/// order, and when a theme runs out another theme follows, preferring one
/// that wasn't just played.
public struct RadioPlan: Sendable {
    public private(set) var theme: MusicLibrary.Theme
    public private(set) var queue: [MusicLibrary.Track]
    private let library: MusicLibrary

    /// `random(n)` returns an index in 0..<n; injected so tests can control it.
    public init?(library: MusicLibrary, random: (Int) -> Int) {
        guard !library.isEmpty else { return nil }
        self.library = library
        theme = library.themes[random(library.themes.count)]
        queue = RadioPlan.shuffled(theme.tracks, random: random)
    }

    /// Takes the next track, moving to another theme when this one is done.
    public mutating func next(random: (Int) -> Int) -> (theme: String, track: MusicLibrary.Track) {
        if queue.isEmpty {
            let others = library.themes.filter { $0 != theme }
            let pool = others.isEmpty ? library.themes : others
            theme = pool[random(pool.count)]
            queue = RadioPlan.shuffled(theme.tracks, random: random)
        }
        return (theme.title, queue.removeFirst())
    }

    static func shuffled(_ tracks: [MusicLibrary.Track], random: (Int) -> Int) -> [MusicLibrary.Track] {
        var result = tracks
        guard result.count > 1 else { return result }
        for i in stride(from: result.count - 1, to: 0, by: -1) {
            result.swapAt(i, random(i + 1))  // Fisher–Yates
        }
        return result
    }
}
