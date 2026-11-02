// Spike 8: can we tell that a call is going on (camera or microphone in use by
// any app) without a permission prompt? Reads only "is this device running
// somewhere" flags: CoreMediaIO for cameras, CoreAudio for input devices.
// Never opens a device, never reads audio or video. Prints every change.
import AppKit
import CoreAudio
import CoreMediaIO

func log(_ text: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    print("\(stamp) \(text)")
    fflush(stdout)
}

// MARK: cameras (CoreMediaIO)

func cameraDevices() -> [CMIOObjectID] {
    var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    var size: UInt32 = 0
    guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
    var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
    var used: UInt32 = 0
    guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &ids) == noErr else { return [] }
    return ids
}

func cameraRunning(_ id: CMIOObjectID) -> Bool {
    var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                                            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
    var running: UInt32 = 0
    var used: UInt32 = 0
    let status = CMIOObjectGetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &running)
    return status == noErr && running != 0
}

func cameraName(_ id: CMIOObjectID) -> String {
    var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOObjectPropertyName),
                                            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    var name: Unmanaged<CFString>?
    var used: UInt32 = 0
    _ = CMIOObjectGetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Unmanaged<CFString>?>.size), &used, &name)
    return (name?.takeRetainedValue() as String?) ?? "camera \(id)"
}

// MARK: microphones (CoreAudio)

func inputDevices() -> [AudioObjectID] {
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                             mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
    return ids.filter { id in
        var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var streamSize: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr && streamSize > 0
    }
}

func micRunning(_ id: AudioObjectID) -> Bool {
    var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                             mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var running: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &running) == noErr && running != 0
}

func micName(_ id: AudioObjectID) -> String {
    var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                             mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var name: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    _ = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name)
    return (name?.takeRetainedValue() as String?) ?? "input \(id)"
}

// MARK: report

var last = ""
func report(_ reason: String) {
    let cams = cameraDevices().map { "\(cameraName($0))=\(cameraRunning($0) ? "ON" : "off")" }
    let mics = inputDevices().map { "\(micName($0))=\(micRunning($0) ? "ON" : "off")" }
    let line = "cameras [\(cams.joined(separator: ", "))] mics [\(mics.joined(separator: ", "))]"
    if line != last {
        log("\(reason): \(line)")
        last = line
    }
}

log("spike 8 started (pid \(getpid()))")
report("at launch")

// Event-driven: listeners on every device's running-somewhere flag.
let queue = DispatchQueue.main
for id in cameraDevices() {
    var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                                            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
    let status = CMIOObjectAddPropertyListenerBlock(id, &address, queue) { _, _ in report("camera listener") }
    log("camera listener on \(cameraName(id)): \(status == noErr ? "ok" : "error \(status)")")
}
for id in inputDevices() {
    var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                             mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    let status = AudioObjectAddPropertyListenerBlock(id, &address, queue) { _, _ in report("mic listener") }
    log("mic listener on \(micName(id)): \(status == noErr ? "ok" : "error \(status)")")
}

// Cross-check with a slow poll, to see whether a listener ever misses a change.
Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in report("5 s poll") }

let seconds = CommandLine.arguments.dropFirst().first.flatMap(Double.init) ?? 600
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
    log("done after \(Int(seconds)) s")
    exit(0)
}
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
