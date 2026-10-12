import Foundation

/// One animation row of a sprite sheet (CLAUDE.md Section 11).
public struct Clip: Codable, Equatable, Sendable {
    public let row: Int
    public let frames: Int
    public let fps: Double
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
        for (name, clip) in all where clip.row < 0 || clip.frames < 1 || clip.fps <= 0 {
            throw SkinError.invalidClip(name)
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

    /// Optional actions this skin actually provides (excluding `submerged`).
    public var availableActions: [String] {
        (manifest.actions ?? [:]).keys.filter { $0 != "submerged" }.sorted()
    }

    public func frameRects(for clip: Clip) -> [FrameRect] {
        let size = manifest.frameSize
        return (0..<clip.frames).map { FrameRect(x: $0 * size, y: clip.row * size, width: size, height: size) }
    }
}
