import AppKit
import Carbon.HIToolbox
import CoreAudio

/// How the hotkey drives the microphone.
enum MicMode: String, CaseIterable, Identifiable {
    case toggle, pushToTalk, pushToMute
    var id: String { rawValue }
    var label: String {
        switch self {
        case .toggle: return "Toggle"
        case .pushToTalk: return "Push to Talk"
        case .pushToMute: return "Push to Mute"
        }
    }
}

/// UserDefaults keys shared by @AppStorage in views and the controller.
enum Prefs {
    static let mode = "mode"
    static let deviceUID = "deviceUID"          // "" = follow system default input
    static let showIndicator = "showIndicator"
    static let indicatorCorner = "indicatorCorner"
    static let playSounds = "playSounds"
    static let restoreOnQuit = "restoreOnQuit"
    static let hotKeyCode = "hotKeyCode"
    static let hotKeyModifiers = "hotKeyModifiers"
    static let hotKeyName = "hotKeyName"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            mode: MicMode.toggle.rawValue, deviceUID: "", showIndicator: true,
            indicatorCorner: ScreenCorner.topRight.rawValue, playSounds: true, restoreOnQuit: true,
            hotKeyCode: kVK_ANSI_M, hotKeyModifiers: controlKey | optionKey, hotKeyName: "M",
        ])
    }
}

/// Central app state: tracks the controlled input device, mirrors its real mute state via
/// CoreAudio listeners, and applies hotkey/mode/indicator/sound behaviour.
final class MicController: ObservableObject {
    static let shared = MicController()

    @Published private(set) var devices: [AudioDevice] = []
    @Published private(set) var current: AudioDevice?
    @Published private(set) var isMuted = false
    @Published private(set) var muteMethod: MuteMethod = .unsupported
    @Published private(set) var selectedDeviceMissing = false
    @Published private(set) var hotKeyError: String?

    private let defaults = UserDefaults.standard
    private let systemListeners = AudioListenerBag()
    private let deviceListeners = AudioListenerBag()
    private let panel = OnAirPanel()
    private var keyHeld = false
    private var lastMode: MicMode?
    private var lastDeviceUID: String?
    private var observers: [NSObjectProtocol] = []

    var mode: MicMode { MicMode(rawValue: defaults.string(forKey: Prefs.mode) ?? "") ?? .toggle }

    private init() {
        Prefs.registerDefaults()
        let system = AudioObjectID(kAudioObjectSystemObject)
        systemListeners.add(system, AudioDevices.address(kAudioHardwarePropertyDevices)) { [weak self] in self?.refreshDevices() }
        systemListeners.add(system, AudioDevices.address(kAudioHardwarePropertyDefaultInputDevice)) { [weak self] in self?.refreshDevices() }

        HotKeyService.shared.onPress = { [weak self] in self?.hotKeyPressed() }
        HotKeyService.shared.onRelease = { [weak self] in self?.hotKeyReleased() }
        registerHotKey()

        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.handleWake() })
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.preferencesChanged() })

        refreshDevices()
        preferencesChanged()
    }

    // MARK: Devices

    func refreshDevices() {
        devices = AudioDevices.inputDevices()
        let wanted = defaults.string(forKey: Prefs.deviceUID) ?? ""
        var target = devices.first { $0.uid == wanted && !wanted.isEmpty }
        selectedDeviceMissing = !wanted.isEmpty && target == nil
        if target == nil, let defaultID = AudioDevices.defaultInputID() {
            target = devices.first { $0.id == defaultID }
        }
        if target == nil { target = devices.first }
        retarget(to: target)
    }

    /// Switches control to `device`, carrying the current mute state over to it.
    private func retarget(to device: AudioDevice?) {
        guard device != current else { readState(); return }
        let previous = current
        let carryMuted = previous != nil ? isMuted : nil
        if let previous, devices.contains(previous), carryMuted == true {
            AudioDevices.setMuted(previous, false) // we no longer control it; leave it live
        }
        current = device
        deviceListeners.removeAll()
        if let device {
            muteMethod = AudioDevices.muteMethod(device.id)
            for selector in [kAudioDevicePropertyMute, kAudioDevicePropertyVolumeScalar] {
                for element in AudioDevices.settableElements(device.id, selector) {
                    deviceListeners.add(device.id, AudioDevices.address(selector, scope: kAudioObjectPropertyScopeInput, element: element)) { [weak self] in
                        self?.readState()
                    }
                }
            }
            if let carryMuted { AudioDevices.setMuted(device, carryMuted) }
        } else {
            muteMethod = .unsupported
        }
        readState(playSound: false)
    }

    private func readState(playSound: Bool = true) {
        let muted = current.map(AudioDevices.isMuted) ?? false
        if muted != isMuted {
            isMuted = muted
            if playSound && defaults.bool(forKey: Prefs.playSounds) {
                NSSound(named: muted ? "Bottle" : "Pop")?.play()
            }
        }
        updateIndicator()
    }

    // MARK: Actions

    func setMuted(_ muted: Bool) {
        guard let current else { return }
        AudioDevices.setMuted(current, muted)
        readState()
    }

    func toggle() { setMuted(!isMuted) }

    private func hotKeyPressed() {
        guard !keyHeld else { return } // ignore auto-repeat
        keyHeld = true
        switch mode {
        case .toggle: toggle()
        case .pushToTalk: setMuted(false)
        case .pushToMute: setMuted(true)
        }
    }

    private func hotKeyReleased() {
        keyHeld = false
        switch mode {
        case .toggle: break
        case .pushToTalk: setMuted(true)
        case .pushToMute: setMuted(false)
        }
    }

    /// A key-up can be lost across sleep; force the mode's resting state.
    private func handleWake() {
        keyHeld = false
        refreshDevices()
        applyRestingState()
    }

    private func applyRestingState() {
        switch mode {
        case .toggle: break
        case .pushToTalk: setMuted(true)
        case .pushToMute: setMuted(false)
        }
    }

    // MARK: Preferences

    private func preferencesChanged() {
        if mode != lastMode {
            lastMode = mode
            keyHeld = false
            applyRestingState()
        }
        let uid = defaults.string(forKey: Prefs.deviceUID) ?? ""
        if uid != lastDeviceUID {
            lastDeviceUID = uid
            refreshDevices()
        }
        updateIndicator()
    }

    private func updateIndicator() {
        if defaults.bool(forKey: Prefs.showIndicator), current != nil, !isMuted {
            let corner = ScreenCorner(rawValue: defaults.string(forKey: Prefs.indicatorCorner) ?? "") ?? .topRight
            panel.show(at: corner)
        } else {
            panel.hide()
        }
    }

    func registerHotKey() {
        hotKeyError = HotKeyService.shared.register(keyCode: defaults.integer(forKey: Prefs.hotKeyCode),
                                                    modifiers: defaults.integer(forKey: Prefs.hotKeyModifiers))
    }

    func suspendHotKey() { HotKeyService.shared.unregister() }

    func prepareForQuit() {
        if defaults.bool(forKey: Prefs.restoreOnQuit), isMuted, let current {
            AudioDevices.setMuted(current, false)
        }
    }
}
