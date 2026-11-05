import Foundation

/// One animation row of a sprite sheet (CLAUDE.md Section 11).
public struct Clip: Codable, Equatable, Sendable {
    public let row: Int
    public let frames: Int
    public let fps: Double
    /// `false`: play once and hold the last frame (e.g. `unplug`). Default true.
    public let loop: Bool?
    /// Frames per sheet row; longer clips continue on the rows below (keeps
    /// the sheet narrow). Default: all frames on one row.
    public let wrap: Int?
    /// Beats one loop spans. When set, the app may play the clip in time
    /// with built-in music instead of at `fps` (the `music` bob).
    public let beats: Int?

    public init(row: Int, frames: Int, fps: Double, loop: Bool? = nil, beats: Int? = nil, wrap: Int? = nil) {
        self.row = row
        self.frames = frames
        self.fps = fps
        self.loop = loop
        self.beats = beats
        self.wrap = wrap
    }

    public var loops: Bool { loop ?? true }
}

/// Optional flower beside Pibbo: one frame per growth stage in `row`.
public struct GardenSpec: Codable, Equatable, Sendable {
    public let row: Int
    public let stages: Int
}

/// A visitor's walk-on: frames played once while the layer steps along the
/// pool. `path[i]` is the layer's left edge during frame i, in art pixels from
/// the window's left edge (meadow 0, flower 16, Pibbo 32 for 16-px frames).
public struct Visit: Codable, Equatable, Sendable {
    public let row: Int
    public let frames: Int
    public let fps: Double
    public let wrap: Int?
    public let path: [Int]

    public init(row: Int, frames: Int, fps: Double, wrap: Int? = nil, path: [Int]) {
        self.row = row
        self.frames = frames
        self.fps = fps
        self.wrap = wrap
        self.path = path
    }

    public var clip: Clip { Clip(row: row, frames: frames, fps: fps, loop: false, wrap: wrap) }
    public var duration: Double { Double(frames) / fps }
}

/// Which sheet colours are the water's glints and its plain surface (see `SkinManifest.moonGlint`).
public struct MoonGlint: Codable, Equatable, Sendable {
    public let glint: String
    public let water: String
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
    /// Holiday extras played over the flower's cell, keyed like `outfits`.
    public let decor: [String: Clip]?
    /// Holiday extras over the meadow's cell (the long rock), keyed like `decor`.
    /// In both, a key "holiday@night" replaces the holiday's decor at night.
    public let meadowDecor: [String: Clip]?
    /// Water colours per time of day ("dawn", "dusk", "night"): hex RGB →
    /// hex RGB. Missing times keep the sheet's own colours.
    public let water: [String: [String: String]]?
    /// Optional long rock left of the flower that fills up over months:
    /// one static frame per stage (`World.Garden.meadowDays`). Needs a garden.
    public let meadow: GardenSpec?
    /// Optional message in a bottle: a looping clip for the flower's cell,
    /// with its own strip of water so it shows while the garden hides.
    public let bottle: Clip?
    /// Optional moonlight at night: the glint colour's night replacement is
    /// mixed toward the plain water's by how dark the moon is (new moon: no
    /// glints). Both are hex RGB source colours of the sheet.
    public let moonGlint: MoonGlint?
    /// Optional one-shot shooting star over the pool on clear nights.
    public let shootingStar: Clip?
    /// Optional weather over the whole pool, keyed "rain" / "snow": looping
    /// clips drawn over every cell (Pibbo's, the flower's, the meadow's).
    public let weatherEffects: [String: Clip]?
    /// Optional snow resting on the rocks: frame 0 for the flower's cell,
    /// frame 1 for the meadow's (static).
    public let snowCover: GardenSpec?
    /// Optional visitors by name ("crab", "seagull", …), see `Visit`.
    public let visitors: [String: Visit]?
    /// Optional present the seagull leaves on the meadow rock (one static
    /// frame over the meadow's cell), shown for good once it has been brought.
    public let gift: GardenSpec?
    /// Optional rainbow after rain: three static frames, for the meadow's,
    /// the flower's and Pibbo's cells, together one arc over the pool.
    public let rainbow: GardenSpec?
    /// Optional things drifting by with the season ("spring", "summer",
    /// "autumn"): a small looping clip in the top-left of a cell; the app
    /// moves it across the pool.
    public let drift: [String: Clip]?
    /// Radio props by name, played over the flower's cell while a theme that
    /// names one plays (theme.json "prop").
    public let props: [String: Clip]?

    public init(id: String, name: String, author: String, version: String, type: String,
                frameSize: Int, states: [String: Clip], actions: [String: Clip]?, garden: GardenSpec? = nil,
                outfits: [String: OutfitSpec]? = nil, poses: [String: String]? = nil,
                transitions: [String: Clip]? = nil, decor: [String: Clip]? = nil, meadowDecor: [String: Clip]? = nil,
                water: [String: [String: String]]? = nil, props: [String: Clip]? = nil,
                meadow: GardenSpec? = nil, bottle: Clip? = nil, moonGlint: MoonGlint? = nil,
                shootingStar: Clip? = nil, weatherEffects: [String: Clip]? = nil, snowCover: GardenSpec? = nil,
                visitors: [String: Visit]? = nil, gift: GardenSpec? = nil, rainbow: GardenSpec? = nil,
                drift: [String: Clip]? = nil) {
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
        self.decor = decor
        self.meadowDecor = meadowDecor
        self.water = water
        self.props = props
        self.meadow = meadow
        self.bottle = bottle
        self.moonGlint = moonGlint
        self.shootingStar = shootingStar
        self.weatherEffects = weatherEffects
        self.snowCover = snowCover
        self.visitors = visitors
        self.gift = gift
        self.rainbow = rainbow
        self.drift = drift
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
        let pack = try SkinPack(manifest: manifest, directory: directory)
        guard let sheet = pngSize(pack.spriteSheetURL) else { throw SkinError.unreadable(pack.spriteSheetURL.path) }
        try checkBounds(manifest, width: sheet.width, height: sheet.height)
        return pack
    }

    /// Rejects skins missing a required state or with impossible clips.
    public static func validate(_ manifest: SkinManifest) throws {
        guard manifest.type == "skin" else { throw SkinError.notASkin(type: manifest.type) }
        guard manifest.frameSize > 0 else { throw SkinError.invalidClip("frameSize must be positive") }
        let missing = requiredStates.filter { manifest.states[$0] == nil }
        guard missing.isEmpty else { throw SkinError.missingStates(missing) }
        for (name, clip) in allClips(manifest)
        where clip.row < 0 || clip.frames < 1 || clip.fps <= 0 || (clip.beats ?? 1) < 1 || (clip.wrap ?? 1) < 1 {
            throw SkinError.invalidClip(name)
        }
        for (name, visit) in manifest.visitors ?? [:] where visit.path.count != visit.frames {
            throw SkinError.invalidClip("visitor \(name)")
        }
        for (name, spec) in allStrips(manifest) where spec.row < 0 || spec.stages < 1 {
            throw SkinError.invalidClip(name)
        }
        for (name, outfit) in manifest.outfits ?? [:] where outfit.offset < 1 {
            throw SkinError.invalidClip("outfit \(name)")
        }
    }

    /// Every animated clip in the manifest, named for error messages.
    static func allClips(_ m: SkinManifest) -> [(String, Clip)] {
        var clips: [(String, Clip)] = []
        func add(_ prefix: String, _ table: [String: Clip]?) {
            clips += (table ?? [:]).map { ("\(prefix)\($0.key)", $0.value) }
        }
        add("", m.states)
        add("", m.actions)
        add("transition ", m.transitions)
        add("decor ", m.decor)
        add("meadow decor ", m.meadowDecor)
        add("prop ", m.props)
        add("weather ", m.weatherEffects)
        add("drift ", m.drift)
        add("visitor ", m.visitors?.mapValues(\.clip))
        if let bottle = m.bottle { clips.append(("bottle", bottle)) }
        if let star = m.shootingStar { clips.append(("shootingStar", star)) }
        return clips
    }

    /// Every static strip (one frame per stage) in the manifest.
    static func allStrips(_ m: SkinManifest) -> [(String, GardenSpec)] {
        [("garden", m.garden), ("meadow", m.meadow), ("snowCover", m.snowCover), ("gift", m.gift), ("rainbow", m.rainbow)]
            .compactMap { name, spec in spec.map { (name, $0) } }
    }

    /// Rejects frames that fall outside a sheet of `width`×`height` pixels,
    /// including every clip's outfit copies.
    public static func checkBounds(_ m: SkinManifest, width: Int, height: Int) throws {
        let size = m.frameSize
        let offsets = [0] + (m.outfits ?? [:]).values.map(\.offset)
        let dressed = Set(Array(m.states.keys) + Array((m.actions ?? [:]).keys))
        for (name, clip) in allClips(m) {
            let perRow = clip.wrap ?? clip.frames
            let columns = min(perRow, clip.frames)
            let rows = (clip.frames + perRow - 1) / perRow
            for offset in dressed.contains(name) || name.hasPrefix("transition ") ? offsets : [0] {
                let bottom = (clip.row + offset + rows) * size
                guard columns * size <= width, bottom <= height else {
                    throw SkinError.invalidClip("\(name) is outside the \(width)×\(height) sheet")
                }
            }
        }
        for (name, spec) in allStrips(m) where spec.stages * size > width || (spec.row + 1) * size > height {
            throw SkinError.invalidClip("\(name) is outside the \(width)×\(height) sheet")
        }
    }

    /// Width and height from a PNG's header (IHDR), without decoding it.
    static func pngSize(_ url: URL) -> (width: Int, height: Int)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 24), header.count == 24,
              header.starts(with: [0x89, 0x50, 0x4E, 0x47]) else { return nil }
        func number(_ range: Range<Int>) -> Int { header[range].reduce(0) { $0 << 8 | Int($1) } }
        return (number(16..<20), number(20..<24))
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
        return (plain.name, Clip(row: clip.row + spec.offset, frames: clip.frames, fps: clip.fps, loop: clip.loop, beats: clip.beats, wrap: clip.wrap))
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
        return Clip(row: clip.row + spec.offset, frames: clip.frames, fps: clip.fps, loop: false, wrap: clip.wrap)
    }

    /// The holiday extras for `holiday`, or nil. They sit in the flower's
    /// cell, so skins without a garden show none.
    public func decor(for holiday: String?, night: Bool = false) -> Clip? {
        guard manifest.garden != nil else { return nil }
        return Self.pick(manifest.decor, holiday: holiday, night: night)
    }

    /// The holiday extras for the meadow's cell (needs a meadow).
    public func meadowDecor(for holiday: String?, night: Bool = false) -> Clip? {
        guard hasMeadow else { return nil }
        return Self.pick(manifest.meadowDecor, holiday: holiday, night: night)
    }

    /// "holiday@night" at night when the skin has it, else "holiday".
    private static func pick(_ table: [String: Clip]?, holiday: String?, night: Bool) -> Clip? {
        guard let holiday, let table else { return nil }
        if night, let nightly = table["\(holiday)@night"] { return nightly }
        return table[holiday]
    }

    /// The radio prop called `name`, or nil. Like decor, it sits in the
    /// flower's cell, so skins without a garden show none.
    public func prop(named name: String?) -> Clip? {
        guard let name, manifest.garden != nil else { return nil }
        return manifest.props?[name]
    }

    /// How to colour the water at a time of day, or nil to keep the sheet's colours.
    /// At night, `moonlight` (0 = new moon, 1 = full) sets how bright the
    /// glints on the water are, when the skin names them (`moonGlint`).
    public func waterTint(for timeOfDay: String?, moonlight: Double = 1) -> WaterTint? {
        guard let timeOfDay, let map = manifest.water?[timeOfDay], let tint = WaterTint(hex: map) else { return nil }
        guard timeOfDay == "night", let moon = manifest.moonGlint,
              let glint = WaterTint.parse(moon.glint), let water = WaterTint.parse(moon.water),
              let litGlint = tint.colors[glint], let dark = tint.colors[water] else { return tint }
        var colors = tint.colors
        colors[glint] = WaterTint.blend(dark, litGlint, moonlight)
        return WaterTint(colors: colors)
    }

    /// Actions the app plays for a reason of its own, never at random.
    public static let systemActions: Set<String> = ["submerged", "unplug", "backfloat", "holdpaw", "look", "ripple"]

    /// Optional actions this skin provides for random/idle use.
    public var availableActions: [String] {
        (manifest.actions ?? [:]).keys.filter { !SkinPack.systemActions.contains($0) }.sorted()
    }

    /// Snow on the rocks: frame for the flower's cell (0) or the meadow's (1).
    public func snowCoverFrameRect(cell: Int) -> FrameRect? {
        guard let cover = manifest.snowCover, cell < cover.stages else { return nil }
        let size = manifest.frameSize
        return FrameRect(x: cell * size, y: cover.row * size, width: size, height: size)
    }

    /// Whether the skin has a meadow (it sits left of the flower, so it needs one).
    public var hasMeadow: Bool { manifest.garden != nil && manifest.meadow != nil }

    /// Frame of the meadow at a stage; nil without one.
    public func meadowFrameRect(stage: Int) -> FrameRect? {
        guard hasMeadow, let meadow = manifest.meadow else { return nil }
        let size = manifest.frameSize
        let clamped = min(max(stage, 0), meadow.stages - 1)
        return FrameRect(x: clamped * size, y: meadow.row * size, width: size, height: size)
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
        let perRow = clip.wrap ?? clip.frames
        return (0..<clip.frames).map {
            FrameRect(x: ($0 % perRow) * size, y: (clip.row + $0 / perRow) * size, width: size, height: size)
        }
    }
}
