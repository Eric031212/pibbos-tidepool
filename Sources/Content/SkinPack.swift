import Foundation

/// One animation row of a sprite sheet (CLAUDE.md Section 11).
public struct Clip: Codable, Equatable, Sendable {
    public let row: Int
    public let frames: Int
    public let fps: Double
    /// `false`: play once and hold the last frame (e.g. `unplug`). Default true.
    public let loop: Bool?
    /// Beats one loop spans. When set, the app may play the clip in time
    /// with built-in music instead of at `fps` (the `music` bob).
    public let beats: Int?

    public init(row: Int, frames: Int, fps: Double, loop: Bool? = nil, beats: Int? = nil) {
        self.row = row
        self.frames = frames
        self.fps = fps
        self.loop = loop
        self.beats = beats
    }

    public var loops: Bool { loop ?? true }
}

/// Optional flower beside Pibbo: one frame per growth stage in `row`.
public struct GardenSpec: Codable, Equatable, Sendable {
    public let row: Int
    public let stages: Int
}

/// Optional holiday outfit: every clip again, `offset` rows further down.
public struct OutfitSpec: Codable, Equatable, Sendable {
    public let offset: Int
}

public struct SkinManifest: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let author: String
    public let version: String
    public let type: String
    public let frameSize: Int
    public let states: [String: Clip]
    public let actions: [String: Clip]?
    public let garden: GardenSpec?
    /// Keyed by holiday (`World.Holiday` raw values), e.g. "halloween".
    public let outfits: [String: OutfitSpec]?
    /// Body pose of each clip (e.g. "low", "up"); clips sharing a pose share
    /// transitions. Clips not listed have no pose.
    public let poses: [String: String]?
    /// In-between clips played once when switching clips, keyed "from>to";
    /// either side is a clip name or "@pose" (see `transition(from:to:)`).
    public let transitions: [String: Clip]?

    public init(id: String, name: String, author: String, version: String, type: String,
                frameSize: Int, states: [String: Clip], actions: [String: Clip]?, garden: GardenSpec? = nil,
                outfits: [String: OutfitSpec]? = nil, poses: [String: String]? = nil,
                transitions: [String: Clip]? = nil) {
        self.id = id
        self.name = name
        self.author = author
        self.version = version
        self.type = type
        self.frameSize = frameSize
        self.states = states
        self.actions = actions
        self.garden = garden
        self.outfits = outfits
        self.poses = poses
        self.transitions = transitions
    }
}

/// Pixel rectangle of one frame in the sprite sheet, origin top-left.
public struct FrameRect: Equatable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
}

public enum SkinError: Error, Equatable {
    case unreadable(String)
    case invalidManifest(String)
    case notASkin(type: String)
    case missingStates([String])
    case invalidClip(String)
}

/// A validated skin pack: `manifest.json` plus `sprites.png` in one folder.
/// Image decoding is left to the platform renderer; this type only knows
/// the layout.
public struct SkinPack: Sendable {
    public static let requiredStates = ["hidden", "peek", "chill", "music", "sleep"]

    public let manifest: SkinManifest
    public let directory: URL

    public var spriteSheetURL: URL { directory.appendingPathComponent("sprites.png") }

    public init(manifest: SkinManifest, directory: URL) throws {
        try SkinPack.validate(manifest)
        self.manifest = manifest
        self.directory = directory
    }

    public static func load(from directory: URL) throws -> SkinPack {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let data: Data
        do {
            data = try Data(contentsOf: manifestURL)
        } catch {
            throw SkinError.unreadable(manifestURL.path)
        }
        let manifest: SkinManifest
        do {
            manifest = try JSONDecoder().decode(SkinManifest.self, from: data)
        } catch {
            throw SkinError.invalidManifest(String(describing: error))
        }
        return try SkinPack(manifest: manifest, directory: directory)
    }

    /// Rejects skins missing a required state or with impossible clips.
    public static func validate(_ manifest: SkinManifest) throws {
        guard manifest.type == "skin" else { throw SkinError.notASkin(type: manifest.type) }
        guard manifest.frameSize > 0 else { throw SkinError.invalidClip("frameSize must be positive") }
        let missing = requiredStates.filter { manifest.states[$0] == nil }
        guard missing.isEmpty else { throw SkinError.missingStates(missing) }
        let all = manifest.states.merging(manifest.actions ?? [:]) { state, _ in state }
            .merging(manifest.transitions ?? [:]) { clip, _ in clip }
        for (name, clip) in all where clip.row < 0 || clip.frames < 1 || clip.fps <= 0 || (clip.beats ?? 1) < 1 {
            throw SkinError.invalidClip(name)
        }
        if let garden = manifest.garden, garden.row < 0 || garden.stages < 1 {
            throw SkinError.invalidClip("garden")
        }
        for (name, outfit) in manifest.outfits ?? [:] where outfit.offset < 1 {
            throw SkinError.invalidClip("outfit \(name)")
        }
    }

    /// The clip to play for a state or action name, applying the fallbacks:
    /// missing `submerged` → `hidden`, any other missing action → `chill`.
    public func resolve(_ name: String) -> (name: String, clip: Clip) {
        if let clip = manifest.states[name] ?? manifest.actions?[name] {
            return (name, clip)
        }
        let fallback = name == "submerged" ? "hidden" : "chill"
        return (fallback, manifest.states[fallback]!)  // required states exist after validation
    }

    /// Like `resolve(_:)`, wearing `outfit` when the skin has it (skins
    /// without that outfit just show the plain clip).
    public func resolve(_ name: String, outfit: String?) -> (name: String, clip: Clip) {
        let plain = resolve(name)
        guard let outfit, let spec = manifest.outfits?[outfit] else { return plain }
        let clip = plain.clip
        return (plain.name, Clip(row: clip.row + spec.offset, frames: clip.frames, fps: clip.fps, loop: clip.loop, beats: clip.beats))
    }

    /// The in-between clip to play once when switching from one resolved clip
    /// to another, or nil to cut straight over. Most specific key wins:
    /// `a>b`, `@poseA>b`, `a>@poseB`, `@poseA>@poseB`.
    public func transition(from: String, to: String, outfit: String? = nil) -> Clip? {
        guard from != to, let transitions = manifest.transitions else { return nil }
        let poses = manifest.poses ?? [:]
        let fromKeys = [from] + (poses[from].map { ["@" + $0] } ?? [])
        let toKeys = [to] + (poses[to].map { ["@" + $0] } ?? [])
        let keys = [(0, 0), (1, 0), (0, 1), (1, 1)].compactMap { i, j -> String? in
            guard i < fromKeys.count, j < toKeys.count else { return nil }
            return fromKeys[i] + ">" + toKeys[j]
        }
        guard let clip = keys.lazy.compactMap({ transitions[$0] }).first else { return nil }
        guard let outfit, let spec = manifest.outfits?[outfit] else { return clip }
        return Clip(row: clip.row + spec.offset, frames: clip.frames, fps: clip.fps, loop: false)
    }

    /// Actions the app plays for a reason of its own, never at random.
    public static let systemActions: Set<String> = ["submerged", "unplug", "backfloat", "holdpaw", "look", "ripple"]

    /// Optional actions this skin provides for random/idle use.
    public var availableActions: [String] {
        (manifest.actions ?? [:]).keys.filter { !SkinPack.systemActions.contains($0) }.sorted()
    }

    /// Frame of the flower at a growth stage; nil when the skin has no garden.
    public func gardenFrameRect(stage: Int) -> FrameRect? {
        guard let garden = manifest.garden else { return nil }
        let size = manifest.frameSize
        let clamped = min(max(stage, 0), garden.stages - 1)
        return FrameRect(x: clamped * size, y: garden.row * size, width: size, height: size)
    }

    public func frameRects(for clip: Clip) -> [FrameRect] {
        let size = manifest.frameSize
        return (0..<clip.frames).map { FrameRect(x: $0 * size, y: clip.row * size, width: size, height: size) }
    }
}
