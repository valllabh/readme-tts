import AppKit
import ApplicationServices
import Carbon.HIToolbox

// Reads the currently selected text in whatever app has focus.
// Tries the Accessibility API first, then falls back to simulating Cmd+C
// while preserving the user's pasteboard contents.
enum SelectionReader {
    static func currentSelection() -> String? {
        if let text = axSelection(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Log.info("selection: AX path, \(text.count) chars")
            return text
        }
        let fallback = pasteboardSelection()
        if let fallback {
            Log.info("selection: pasteboard path, \(fallback.count) chars")
        } else {
            Log.info("selection: both paths empty (AX no selected text, pasteboard unchanged after Cmd C)")
        }
        return fallback
    }

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func ensureAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // When the app is untrusted, any existing permission rows belong to an
    // older build signature and can never match again. They make System
    // Settings show ReadMe as enabled while the API still refuses, which is
    // confusing. Clearing them first means the next grant records cleanly.
    static func resetStalePermission() {
        guard !isTrusted, let bundleID = Bundle.main.bundleIdentifier else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleID]
        try? process.run()
        process.waitUntilExit()
    }

    static func openAccessibilitySettings() {
        let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: pane) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Accessibility path

    private static func axSelection() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success, let focusedRef else { return nil }
        let focused = focusedRef as! AXUIElement

        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            &valueRef
        ) == .success, let text = valueRef as? String, !text.isEmpty {
            return text
        }
        return nil
    }

    // MARK: - Pasteboard fallback

    private static func pasteboardSelection() -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = snapshotPasteboard(pasteboard)
        let oldCount = pasteboard.changeCount

        postCopyKeystroke()

        let deadline = Date().addingTimeInterval(0.5)
        while pasteboard.changeCount == oldCount && Date() < deadline {
            usleep(20_000)
        }

        guard pasteboard.changeCount != oldCount else { return nil }
        let text = pasteboard.string(forType: .string)
        restorePasteboard(pasteboard, snapshot: snapshot)
        return text
    }

    private static func snapshotPasteboard(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    entry[type] = data
                }
            }
            return entry
        }
    }

    private static func restorePasteboard(
        _ pasteboard: NSPasteboard,
        snapshot: [[NSPasteboard.PasteboardType: Data]]
    ) {
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }
        let items = snapshot.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(items)
    }

    private static func postCopyKeystroke() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
