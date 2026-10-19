import SwiftUI

/// The menu bar popover: big mute button, device and mode pickers, and app actions.
struct MenuView: View {
    @EnvironmentObject private var mic: MicController
    @Environment(\.openSettings) private var openSettings
    @AppStorage(Prefs.deviceUID) private var deviceUID = ""
    @AppStorage(Prefs.mode) private var mode = MicMode.toggle.rawValue
    @AppStorage(Prefs.hotKeyName) private var hotKeyName = "M"
    @AppStorage(Prefs.hotKeyModifiers) private var hotKeyModifiers = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if mic.devices.isEmpty {
                Label("No microphone found", systemImage: "mic.badge.xmark")
                    .font(.headline)
                Text("Connect an input device and it will appear here automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Button { mic.toggle() } label: {
                    Label(mic.isMuted ? "Unmute" : "Mute", systemImage: mic.isMuted ? "mic.fill" : "mic.slash.fill")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .tint(mic.isMuted ? .green : .red)
                .disabled(mic.muteMethod == .unsupported)

                Text("\(mic.isMuted ? "Muted" : "Live") · \(HotKeyService.display(keyName: hotKeyName, modifiers: hotKeyModifiers))")
                    .font(.caption).foregroundStyle(.secondary)

                Picker("Input", selection: $deviceUID) {
                    Text("System Default").tag("")
                    ForEach(mic.devices) { Text($0.name).tag($0.uid) }
                }
                DeviceWarnings()

                Picker("Mode", selection: $mode) {
                    ForEach(MicMode.allCases) { Text($0.label).tag($0.rawValue) }
                }
            }

            Divider()
            Button("Support / Donate ❤️") { Support.openDonation() }
            HStack {
                Button("Settings…") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 280)
    }
}

/// Explains device problems: missing selection, or no system mute control.
struct DeviceWarnings: View {
    @EnvironmentObject private var mic: MicController

    var body: some View {
        if mic.selectedDeviceMissing, let current = mic.current {
            Text("Selected device is unavailable — controlling \(current.name) instead.")
                .font(.caption).foregroundStyle(.orange)
        }
        switch mic.muteMethod {
        case .hardwareMute: EmptyView()
        case .volumeFallback:
            Label("This device can't be muted by the system. HushSwitch will drop its input volume to zero instead and restore it on unmute.",
                  systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        case .unsupported:
            Label("This device supports neither mute nor input volume control, so it can't be silenced.",
                  systemImage: "xmark.octagon")
                .font(.caption).foregroundStyle(.red)
        }
    }
}
