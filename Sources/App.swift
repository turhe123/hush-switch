import AppKit
import SwiftUI

/// App entry point: a menu bar extra plus a Settings window.
@main
struct HushSwitchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var mic = MicController.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(mic)
        } label: {
            Image(nsImage: Self.statusIcon(muted: mic.isMuted))
                .accessibilityLabel(mic.isMuted ? "Microphone muted" : "Microphone live")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environmentObject(mic)
        }
    }

    /// Red slashed mic when muted; a regular template mic when live.
    static func statusIcon(muted: Bool) -> NSImage {
        let name = muted ? "mic.slash.fill" : "mic.fill"
        var config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        if muted { config = config.applying(.init(paletteColors: [.systemRed])) }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) ?? NSImage()
        image.isTemplate = !muted
        return image
    }
}

/// Handles app lifecycle hooks: restores the mic on quit according to the user's setting.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        MicController.shared.prepareForQuit()
    }
}

/// Opens the project's donation page.
enum Support {
    static func openDonation() {
        NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
    }
}
