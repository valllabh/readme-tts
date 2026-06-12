import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ReadMeCore

// Reads the currently selected text in whatever app has focus.
// Tries the Accessibility API first, then falls back to simulating Cmd+C
// while preserving the user's pasteboard contents. Browsers invert the
// order: their AX selected text flattens page structure (headings glue to
// body, figures leak captions, tables lose rows), while their pasteboard
// carries an HTML flavor with the structure intact.
enum SelectionReader {
    static func currentSelection() -> String? {
        if frontmostIsBrowser, let copied = pasteboardSelection() {
            Log.info("selection: browser pasteboard path, \(copied.count) chars")
            return copied
        }
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

    private static let browserBundleIDs: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
        "com.microsoft.edgemac", "com.google.Chrome", "com.google.Chrome.canary",
        "org.mozilla.firefox", "com.brave.Browser", "com.vivaldi.Vivaldi",
        "company.thebrowser.Browser", "com.operasoftware.Opera",
    ]

    private static var frontmostIsBrowser: Bool {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return browserBundleIDs.contains(id)
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

    // Fast AX only read for the resume check: no pasteboard fallback, no
    // synthesized keystrokes, returns nil when the app exposes nothing.
    static func quickSelection() -> String? {
        axSelection()
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

        // Fine grained polling keeps the happy path fast; the timeout only
        // bounds the no selection case.
        let deadline = Date().addingTimeInterval(0.3)
        while pasteboard.changeCount == oldCount && Date() < deadline {
            usleep(10_000)
        }

        guard pasteboard.changeCount != oldCount else { return nil }
        let html = pasteboard.string(forType: .html)
        let plain = pasteboard.string(forType: .string)
        restorePasteboard(pasteboard, snapshot: snapshot)

        // HTML flavor first: it preserves headings, paragraphs, and table
        // rows that the plain flavor flattens, and drops images cleanly.
        if let html {
            let text = HTMLTextExtractor.text(fromHTML: html)
            if !text.isEmpty {
                Log.info("selection: html flavor, \(html.count) chars html, \(text.count) chars text")
                return text
            }
        }
        return plain
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
