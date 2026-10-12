// Spike 1: external music notifications.
// Listens for Apple Music and Spotify distributed notifications and prints
// everything they carry. Uses only DistributedNotificationCenter: no
// AppleScript, Apple Events, ScriptingBridge, MediaRemote, or private APIs.

import Foundation

setvbuf(stdout, nil, _IOLBF, 0)  // line-buffered so `| tee` shows output live

let names = [
    "com.apple.Music.playerInfo",
    "com.spotify.client.PlaybackStateChanged",
]

let timestampFormatter = ISO8601DateFormatter()
timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

/// Describes a value's runtime type. NSNumber also reports its ObjC encoding
/// (c = BOOL, q = Int64, d = Double, ...) so we can tell bools from ints.
func typeDescription(_ value: Any) -> String {
    if let number = value as? NSNumber {
        let isBool = CFGetTypeID(number) == CFBooleanGetTypeID()
        let encoding = String(cString: number.objCType)
        return "\(type(of: value)) objCType=\(encoding)\(isBool ? " (CFBoolean)" : "")"
    }
    return String(describing: type(of: value))
}

func dump(_ value: Any, indent: String) {
    switch value {
    case let dict as [AnyHashable: Any]:
        for (key, child) in dict.sorted(by: { "\($0.key)" < "\($1.key)" }) {
            if child is [AnyHashable: Any] || child is [Any] {
                print("\(indent)\(key) <\(typeDescription(child))>:")
                dump(child, indent: indent + "    ")
            } else {
                print("\(indent)\(key) = \(String(reflecting: child)) <\(typeDescription(child))>")
            }
        }
    case let array as [Any]:
        for (index, child) in array.enumerated() {
            print("\(indent)[\(index)] = \(String(reflecting: child)) <\(typeDescription(child))>")
        }
    default:
        print("\(indent)\(String(reflecting: value)) <\(typeDescription(value))>")
    }
}

let center = DistributedNotificationCenter.default()
for name in names {
    center.addObserver(
        forName: Notification.Name(name),
        object: nil,
        queue: .main
    ) { note in
        let stamp = timestampFormatter.string(from: Date())
        print("──── \(stamp)  \(note.name.rawValue)")
        print("  object = \(String(describing: note.object))")
        if let info = note.userInfo, !info.isEmpty {
            print("  userInfo (\(info.count) keys):")
            dump(info, indent: "    ")
        } else {
            print("  userInfo = <none>")
        }
        print("")
    }
}

print("[\(timestampFormatter.string(from: Date()))] listening for:")
names.forEach { print("  - \($0)") }
print("Press Ctrl+C to quit.\n")

RunLoop.main.run()
