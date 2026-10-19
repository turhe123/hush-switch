# HushSwitch — specification

**Tagline:** One global hotkey to mute or unmute your microphone in any app, with push-to-talk and an on-air indicator.

**Category:** Audio

**Inspired by (paid):** Mic Drop ($5 one-time)

**Frameworks:** SwiftUI, AppKit, CoreAudio, Carbon, ServiceManagement

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does: Mic Drop is a menu bar app that mutes and unmutes the system microphone with a global shortcut and supports push-to-talk and push-to-mute. It is free to try with a 30 day trial and unlocks pro features through a Super Pro purchase of 5 dollars, and a newer version 3.0 was launched on Product Hunt in 2026. Six Colors wrote about it, and several competing mute apps (MuteKey, Mutify, Shush, MicControl) are sold at similar low prices, which shows steady remote-work demand. Our clean-room HushSwitch covers the same core idea.

Feature set: toggle mute on the selected input device with a recorded global hotkey, a push-to-talk mode where the mic is muted until a key is held, a push-to-mute mode, a choice of which input device to control (default or a specific one), a menu bar icon that clearly shows muted or live state, an optional floating on-air pill that appears only while the mic is live, and optional sound cues on state changes. Preserve the mute state when the user switches devices. About 350 to 500 lines.

UI spec: a MenuBarExtra whose icon is a microphone, slashed and red when muted. The menu has a large Mute or Unmute button, an input device picker, mode picker (Toggle, Push to talk, Push to mute), and Settings, Quit. Settings window: hotkey recorder, mode, show floating indicator toggle with a corner picker, play sounds toggle, launch at login toggle. Floating indicator is a small borderless NSPanel at screen level status that ignores mouse events. Empty state: if no input devices are available, show a message that no microphone was found. Warn when the chosen device cannot be muted by the system, with a note that the app can instead drop the input volume to zero as a fallback.

Technical approach: CoreAudio. Enumerate input devices, read and write kAudioDevicePropertyMute on the input scope, and when the device has no mute property, store the old input volume and set kAudioDevicePropertyVolumeScalar to zero, restoring it on unmute. Listen for default input changes and mute property changes with AudioObjectAddPropertyListenerBlock so the icon always reflects reality even if another app changes it. Global hotkeys use Carbon RegisterEventHotKey and need no permission. Push-to-talk needs key-up detection, which Carbon hot keys provide through both pressed and released event kinds. No microphone permission is required because the app only changes device properties and never records audio. Persist settings with AppStorage. Launch at login via SMAppService.mainApp.

Edge cases: if the hotkey is already used by the system, show an error in the recorder. If the user quits while muted, restore the live state or keep it muted according to a setting, and default to restoring. Handle devices that disappear mid-session by falling back to the new default input and refreshing the icon. For push-to-talk, a lost key-up event after sleep should force a re-mute when the app wakes, using the NSWorkspace did wake notification. Avoid double-toggling from key repeat by ignoring repeated pressed events. Make sure restoring the volume uses the stored value rather than a hard-coded one, and sanity check that stored volume is above zero before restoring.
