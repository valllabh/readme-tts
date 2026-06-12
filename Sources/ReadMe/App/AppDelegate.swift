import ReadMeCore
import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let speech = SpeechController()
    private var statusBar: StatusBarController!
    private var hotkeys: HotkeyManager!
    private var services: ServicesProvider!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unbundled"
        Log.info("launch: v\(version) build \(build), \(Bundle.main.bundlePath), macOS \(ProcessInfo.processInfo.operatingSystemVersionString), trusted=\(SelectionReader.isTrusted)")
        // First launch after an install with a changed signature: clear the
        // stale permission rows so the fresh grant sticks, then prompt.
        SelectionReader.resetStalePermission()
        SelectionReader.ensureAccessibilityPermission()

        statusBar = StatusBarController(speech: speech)

        hotkeys = HotkeyManager()
        applyShortcuts()
        NotificationCenter.default.addObserver(
            forName: Preferences.shortcutsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyShortcuts()
        }

        services = ServicesProvider(speech: speech)
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()

        // Debug path: ReadMe --filter-test "raw text" prints the regex
        // pipeline result and the Gemma filter result side by side, no audio.
        if let index = CommandLine.arguments.firstIndex(of: "--filter-test"),
           CommandLine.arguments.count > index + 1 {
            let text = CommandLine.arguments[index + 1]
            Task {
                let regexStart = Date()
                let chunks = SentenceChunker.chunks(for: TextNormalizer.normalize(text))
                let regexSeconds = Date().timeIntervalSince(regexStart)
                print("=== REGEX PIPELINE (\(String(format: "%.4f", regexSeconds))s) ===")
                for (i, chunk) in chunks.enumerated() {
                    print("[chunk \(i + 1), pause \(chunk.pauseAfter)s] \(chunk.text)")
                }
                let (gemma, seconds) = await ScriptPreparer.shared.filterExperiment(text)
                print("=== GEMMA FILTER (\(String(format: "%.2f", seconds))s) ===")
                print(gemma)
                exit(0)
            }
            return
        }

        // Debug path: ReadMe --speak "some text" speaks immediately without
        // touching the selection.
        if let index = CommandLine.arguments.firstIndex(of: "--speak"),
           CommandLine.arguments.count > index + 1 {
            let text = CommandLine.arguments[(index + 1)...].joined(separator: " ")
            var spoke = false
            speech.onStatusChange = { status in
                if status == .speaking {
                    spoke = true
                }
                if status == .idle && spoke {
                    NSApp.terminate(nil)
                }
            }
            Task { [speech] in
                await EngineManager.shared.warmUp(Preferences.engine)
                if Preferences.aiScriptEnabled {
                    await ScriptPreparer.shared.warmUp()
                }
                speech.read(text)
            }
            // Debug: verify the preferences window opens while reading.
            if CommandLine.arguments.contains("--prefs-test") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                    PreferencesWindowController.shared.show()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        let window = PreferencesWindowController.shared.window
                        NSLog("PREFS_TEST visible=\(window?.isVisible ?? false) key=\(window?.isKeyWindow ?? false)")
                    }
                }
            }
            return
        }

        // Preload the engine and the script polish model so the first read
        // starts fast and polished.
        Task {
            await EngineManager.shared.warmUp(Preferences.engine)
            if Preferences.aiScriptEnabled {
                await ScriptPreparer.shared.warmUp()
            }
        }
    }

    // Registers the three global shortcuts from preferences. The default for
    // readOrStop is Option Escape, the macOS accessibility Speak Selection
    // shortcut, so the system reading trigger drives ReadMe.
    private func applyShortcuts() {
        hotkeys.unregisterAll()
        for (id, action) in ShortcutAction.allCases.enumerated() {
            let shortcut = Preferences.shortcut(for: action)
            Log.info("hotkey: \(action.rawValue) keyCode=\(shortcut.keyCode) modifiers=\(shortcut.modifiers)")
            hotkeys.register(
                id: UInt32(id + 1),
                keyCode: shortcut.keyCode,
                modifiers: shortcut.modifiers
            ) { [weak self] in
                Log.info("hotkey fired: \(action.rawValue)")
                self?.perform(action)
            }
        }
    }

    private func perform(_ action: ShortcutAction) {
        switch action {
        case .read:
            speech.readSelection()
        case .pauseResume:
            speech.togglePause()
        case .readOrStop:
            // Speak Selection style toggle: read when idle, stop otherwise.
            if speech.status == .idle {
                speech.readSelection()
            } else {
                speech.stop()
            }
        }
    }
}
