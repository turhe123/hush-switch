import AppKit
import ServiceManagement
import SwiftUI

/// Settings window: hotkey, mode, indicator, sounds, quit behaviour and launch at login.
struct SettingsView: View {
    @EnvironmentObject private var mic: MicController
    @AppStorage(Prefs.mode) private var mode = MicMode.toggle.rawValue
    @AppStorage(Prefs.showIndicator) private var showIndicator = true
    @AppStorage(Prefs.indicatorCorner) private var corner = ScreenCorner.topRight.rawValue
    @AppStorage(Prefs.playSounds) private var playSounds = true
    @AppStorage(Prefs.restoreOnQuit) private var restoreOnQuit = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Shortcut") {
                LabeledContent("Global hotkey") { HotKeyRecorder() }
                Picker("Mode", selection: $mode) {
                    ForEach(MicMode.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Text("No permissions are needed: HushSwitch only changes device settings and never records audio.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Feedback") {
                Toggle("Show floating on-air indicator while live", isOn: $showIndicator)
                Picker("Indicator corner", selection: $corner) {
                    ForEach(ScreenCorner.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .disabled(!showIndicator)
                Toggle("Play sounds on mute / unmute", isOn: $playSounds)
            }
            Section("General") {
                Toggle("Unmute the microphone when quitting", isOn: $restoreOnQuit)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
            Section {
                Button("Support / Donate ❤️") { Support.openDonation() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't update login item: \(error.localizedDescription). You can add HushSwitch manually in System Settings › General › Login Items."
        }
        let actual = SMAppService.mainApp.status == .enabled
        if actual != launchAtLogin { launchAtLogin = actual }
    }
}

/// Click-to-record control that captures a key combination and registers it as the global hotkey.
struct HotKeyRecorder: View {
    @EnvironmentObject private var mic: MicController
    @AppStorage(Prefs.hotKeyCode) private var keyCode = 0
    @AppStorage(Prefs.hotKeyModifiers) private var modifiers = 0
    @AppStorage(Prefs.hotKeyName) private var keyName = "M"
    @State private var recording = false
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button(recording ? "Type shortcut… (Esc to cancel)" : HotKeyService.display(keyName: keyName, modifiers: modifiers)) {
                recording ? stop() : start()
            }
            .frame(minWidth: 140)
            if let message = hint ?? mic.hotKeyError {
                Text(message).font(.caption).foregroundStyle(.red).multilineTextAlignment(.trailing)
            }
        }
        .onDisappear { if recording { stop() } }
    }

    private func start() {
        hint = nil
        recording = true
        mic.suspendHotKey() // so the current combo reaches us instead of firing
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53 { stop(); return } // Esc
        let mods = HotKeyService.carbonModifiers(event.modifierFlags)
        let isFunctionKey = HotKeyService.functionKeys[Int(event.keyCode)] != nil
        guard mods != 0 || isFunctionKey else {
            hint = "Add at least one modifier (⌃ ⌥ ⇧ ⌘) or use a function key."
            return
        }
        hint = nil
        keyCode = Int(event.keyCode)
        modifiers = mods
        keyName = HotKeyService.keyName(for: event)
        stop()
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        mic.registerHotKey()
    }
}
