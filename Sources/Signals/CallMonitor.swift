import CoreAudio
import CoreMediaIO
import Foundation

/// Tells whether a call is probably going on: any camera or microphone in use
/// by any app (spike 8). Reads only each device's "running somewhere" flag:
/// it never opens a device or touches audio or video, so no permission
/// prompt. Event-driven (property listeners), no polling.
///
/// Debounced so a blip (Siri, a quick dictation) doesn't make Pibbo dive:
/// a call starts after `startDelay` of use and ends after `endDelay` of quiet.
final class CallMonitor {
    var onChange: ((Bool) -> Void)?
    private(set) var inCall = false

    private let startDelay: TimeInterval = 2
    private let endDelay: TimeInterval = 5
    private var pending: DispatchWorkItem?
    private var watchedCameras: Set<CMIOObjectID> = []
    private var watchedMics: Set<AudioObjectID> = []

    func start() {
        // New devices (an iPhone camera, a headset) come and go: re-watch on changes.
        var cameraList = Self.cmioAddress(kCMIOHardwarePropertyDevices, scope: kCMIOObjectPropertyScopeGlobal)
        CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &cameraList, .main) { [weak self] _, _ in
            self?.watchDevices()
        }
        var micList = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &micList, .main) { [weak self] _, _ in
            self?.watchDevices()
        }
        watchDevices()
    }

    private func watchDevices() {
        for camera in Self.cameras() where !watchedCameras.contains(camera) {
            var address = Self.cmioAddress(kCMIODevicePropertyDeviceIsRunningSomewhere, scope: kCMIOObjectPropertyScopeWildcard)
            if CMIOObjectAddPropertyListenerBlock(camera, &address, .main, { [weak self] _, _ in self?.devicesChanged() }) == noErr {
                watchedCameras.insert(camera)
            }
        }
        for mic in Self.microphones() where !watchedMics.contains(mic) {
            var address = Self.micRunningAddress
            if AudioObjectAddPropertyListenerBlock(mic, &address, .main, { [weak self] _, _ in self?.devicesChanged() }) == noErr {
                watchedMics.insert(mic)
            }
        }
        devicesChanged()
    }

    private func devicesChanged() {
        let active = Self.cameras().contains(where: Self.cameraRunning) || Self.microphones().contains(where: Self.micRunning)
        pending?.cancel()
        guard active != inCall else { return }
        let change = DispatchWorkItem { [weak self] in
            guard let self, self.inCall != active else { return }
            self.inCall = active
            self.onChange?(active)
        }
        pending = change
        DispatchQueue.main.asyncAfter(deadline: .now() + (active ? startDelay : endDelay), execute: change)
    }

    // MARK: - Cameras (CoreMediaIO)

    private static func cmioAddress(_ selector: some BinaryInteger, scope: some BinaryInteger) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(selector),
                                  mScope: CMIOObjectPropertyScope(scope),
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private static func cameras() -> [CMIOObjectID] {
        var address = cmioAddress(kCMIOHardwarePropertyDevices, scope: kCMIOObjectPropertyScopeGlobal)
        var size: UInt32 = 0
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &ids) == noErr else { return [] }
        return ids
    }

    private static func cameraRunning(_ camera: CMIOObjectID) -> Bool {
        var address = cmioAddress(kCMIODevicePropertyDeviceIsRunningSomewhere, scope: kCMIOObjectPropertyScopeWildcard)
        var running: UInt32 = 0
        var used: UInt32 = 0
        return CMIOObjectGetPropertyData(camera, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &running) == noErr
            && running != 0
    }

    // MARK: - Microphones (CoreAudio)

    private static let micRunningAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

    private static func microphones() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter { id in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                     mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            return AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr && streamSize > 0
        }
    }

    private static func micRunning(_ mic: AudioObjectID) -> Bool {
        var address = micRunningAddress
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(mic, &address, 0, nil, &size, &running) == noErr && running != 0
    }
}
