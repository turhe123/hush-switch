import CoreAudio
import Foundation

/// An audio input device as seen by CoreAudio.
struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

/// How a device can be silenced.
enum MuteMethod {
    case hardwareMute     // kAudioDevicePropertyMute is settable
    case volumeFallback   // no mute control; drop input volume to zero instead
    case unsupported
}

/// Thin, stateless wrapper around the CoreAudio C API for input devices: enumeration,
/// mute/volume reads and writes, and the volume-to-zero fallback.
enum AudioDevices {
    private static let system = AudioObjectID(kAudioObjectSystemObject)
    private static let input = kAudioObjectPropertyScopeInput

    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func inputDevices() -> [AudioDevice] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter { inputChannelCount($0) > 0 }.compactMap { id in
            guard let uid = string(id, kAudioDevicePropertyDeviceUID) else { return nil }
            return AudioDevice(id: id, uid: uid, name: string(id, kAudioObjectPropertyName) ?? "Unknown Device")
        }
    }

    static func defaultInputID() -> AudioDeviceID? {
        var addr = address(kAudioHardwarePropertyDefaultInputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &id) == noErr, id != kAudioObjectUnknown else { return nil }
        return id
    }

    static func inputChannelCount(_ id: AudioDeviceID) -> Int {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope: input)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    /// Elements (main, or per-channel) on which `selector` is settable in the input scope.
    static func settableElements(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> [AudioObjectPropertyElement] {
        let channels = (1...max(1, inputChannelCount(id))).map { AudioObjectPropertyElement($0) }
        for candidates in [[kAudioObjectPropertyElementMain], channels] {
            let ok = candidates.filter { element in
                var addr = address(selector, scope: input, element: element)
                guard AudioObjectHasProperty(id, &addr) else { return false }
                var settable: DarwinBoolean = false
                return AudioObjectIsPropertySettable(id, &addr, &settable) == noErr && settable.boolValue
            }
            if !ok.isEmpty { return ok }
        }
        return []
    }

    static func muteMethod(_ id: AudioDeviceID) -> MuteMethod {
        if !settableElements(id, kAudioDevicePropertyMute).isEmpty { return .hardwareMute }
        if !settableElements(id, kAudioDevicePropertyVolumeScalar).isEmpty { return .volumeFallback }
        return .unsupported
    }

    private static func get<T>(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector, _ element: AudioObjectPropertyElement, _ initial: T) -> T? {
        var addr = address(selector, scope: input, element: element)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0) }
        return status == noErr ? value : nil
    }

    @discardableResult
    private static func set<T>(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector, _ element: AudioObjectPropertyElement, _ value: T) -> Bool {
        var addr = address(selector, scope: input, element: element)
        var value = value
        return withUnsafePointer(to: &value) { AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<T>.size), $0) } == noErr
    }

    static func isMuted(_ device: AudioDevice) -> Bool {
        switch muteMethod(device.id) {
        case .hardwareMute:
            return settableElements(device.id, kAudioDevicePropertyMute).contains {
                (get(device.id, kAudioDevicePropertyMute, $0, UInt32(0)) ?? 0) != 0
            }
        case .volumeFallback:
            return settableElements(device.id, kAudioDevicePropertyVolumeScalar).allSatisfy {
                (get(device.id, kAudioDevicePropertyVolumeScalar, $0, Float32(1)) ?? 1) <= 0.0001
            }
        case .unsupported:
            return false
        }
    }

    private static func savedVolumeKey(_ device: AudioDevice) -> String { "savedVolume.\(device.uid)" }

    /// Mutes or unmutes `device`. Devices without a mute control get their input volume
    /// stored and set to zero; unmuting restores the stored value.
    @discardableResult
    static func setMuted(_ device: AudioDevice, _ muted: Bool) -> Bool {
        switch muteMethod(device.id) {
        case .hardwareMute:
            let elements = settableElements(device.id, kAudioDevicePropertyMute)
            return elements.map { set(device.id, kAudioDevicePropertyMute, $0, UInt32(muted ? 1 : 0)) }.allSatisfy { $0 }
        case .volumeFallback:
            let elements = settableElements(device.id, kAudioDevicePropertyVolumeScalar)
            let key = savedVolumeKey(device)
            let defaults = UserDefaults.standard
            if muted {
                if let first = elements.first,
                   let current = get(device.id, kAudioDevicePropertyVolumeScalar, first, Float32(0)), current > 0 {
                    defaults.set(current, forKey: key)
                }
                return elements.map { set(device.id, kAudioDevicePropertyVolumeScalar, $0, Float32(0)) }.allSatisfy { $0 }
            }
            // Sanity check: only restore a stored volume that is actually audible.
            let stored = defaults.float(forKey: key)
            let restore: Float32 = stored > 0 && stored <= 1 ? stored : 0.5
            defaults.removeObject(forKey: key)
            return elements.map { set(device.id, kAudioDevicePropertyVolumeScalar, $0, restore) }.allSatisfy { $0 }
        case .unsupported:
            return false
        }
    }
}

/// Owns CoreAudio property listener blocks so they can be removed again later.
final class AudioListenerBag {
    private var entries: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    func add(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress, _ handler: @escaping () -> Void) {
        var addr = addr
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        if AudioObjectAddPropertyListenerBlock(object, &addr, DispatchQueue.main, block) == noErr {
            entries.append((object, addr, block))
        }
    }

    func removeAll() {
        for (object, addr, block) in entries {
            var addr = addr
            AudioObjectRemovePropertyListenerBlock(object, &addr, DispatchQueue.main, block)
        }
        entries.removeAll()
    }

    deinit { removeAll() }
}
