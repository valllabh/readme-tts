import AppKit
import Carbon.HIToolbox
import ReadMeCore
import ServiceManagement
import SwiftUI

// The Settings panel of the main app window (MainWindow.swift).
struct PreferencesView: View {
    @State private var engine = Preferences.engine
    @State private var voice = Preferences.voice
    @State private var aiScript = Preferences.aiScriptEnabled
    @State private var debugMode = Preferences.debugMode
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            NSLog("ReadMe: launch at login failed (\(error))")
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            Section("Voice") {
                Picker("Model", selection: $engine) {
                    ForEach(EngineKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .onChange(of: engine) { _, kind in
                    Preferences.engine = kind
                    voice = kind.defaultVoice ?? ""
                    Preferences.voice = voice
                    Task {
                        await EngineManager.shared.warmUp(kind)
                    }
                }

                Picker("Voice", selection: $voice) {
                    ForEach(engine.voices, id: \.id) { v in
                        Text(v.name).tag(v.id)
                    }
                }
                .onChange(of: voice) { _, v in
                    Preferences.voice = v
                }

                Toggle("AI Script Polish", isOn: $aiScript)
                    .onChange(of: aiScript) { _, enabled in
                        Preferences.aiScriptEnabled = enabled
                        if enabled {
                            Task {
                                await ScriptPreparer.shared.warmUp()
                            }
                        }
                    }
                Text("A small local language model rewrites each chunk for natural reading, one chunk ahead of speech.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Shortcuts") {
                ForEach(ShortcutAction.allCases, id: \.self) { action in
                    ShortcutRecorderRow(action: action)
                }
                Text("Click a shortcut, then press the new keys. Plain Escape cancels recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Debug") {
                Toggle("Debug Mode", isOn: $debugMode)
                    .onChange(of: debugMode) { _, enabled in
                        Preferences.debugMode = enabled
                        Log.info("prefs: debug mode \(enabled ? "on" : "off")")
                        if enabled {
                            DebugTrace.append("polish system prompt", ScriptPreparer.instructions)
                        }
                    }
                Text("Traces every chunk sent to the voice plus AI polish input and output into the log, live in the Logs panel. Spoken text is written to disk while on, so keep it off in normal use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutRecorderRow: View {
    let action: ShortcutAction

    @State private var shortcut: Shortcut
    @State private var recording = false
    @State private var monitor: Any?

    init(action: ShortcutAction) {
        self.action = action
        _shortcut = State(initialValue: Preferences.shortcut(for: action))
    }

    var body: some View {
        HStack {
            Text(action.displayName)
            Spacer()
            Button(recording ? "Press keys…" : KeyDisplay.string(for: shortcut)) {
                if recording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            DispatchQueue.main.async {
                handle(event)
            }
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        let mods = KeyDisplay.carbonModifiers(from: event.modifierFlags)
        // Plain Escape cancels recording.
        if event.keyCode == UInt16(kVK_Escape) && mods == 0 {
            stopRecording()
            return
        }
        let new = Shortcut(keyCode: UInt32(event.keyCode), modifiers: mods)
        shortcut = new
        Preferences.setShortcut(new, for: action)
        stopRecording()
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        recording = false
    }
}

enum KeyDisplay {
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        return mods
    }

    static func string(for shortcut: Shortcut) -> String {
        var parts = ""
        if shortcut.modifiers & UInt32(controlKey) != 0 { parts += "⌃" }
        if shortcut.modifiers & UInt32(optionKey) != 0 { parts += "⌥" }
        if shortcut.modifiers & UInt32(shiftKey) != 0 { parts += "⇧" }
        if shortcut.modifiers & UInt32(cmdKey) != 0 { parts += "⌘" }
        return parts + keyName(shortcut.keyCode)
    }

    private static let names: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 25: "9", 26: "7", 28: "8", 29: "0", 30: "]", 31: "O",
        32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J", 39: "'",
        40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M",
        47: ".", 50: "`", 36: "↩", 48: "⇥", 49: "Space", 51: "⌫",
        53: "⎋", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    private static func keyName(_ code: UInt32) -> String {
        names[code] ?? "Key \(code)"
    }
}
