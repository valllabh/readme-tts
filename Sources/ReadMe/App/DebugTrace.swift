import AppKit
import ReadMeCore

// Development visibility: when Debug Mode is on, every stage of the pipeline
// appends here and a live window shows exactly what each chunk sends to the
// TTS, what goes into the polish model, and what comes back. Off by default;
// nothing is captured when disabled.
enum DebugTrace {
    static func append(_ tag: String, _ text: String) {
        guard Preferences.debugMode else { return }
        Task { @MainActor in
            DebugWindowController.shared.append(tag, text)
        }
        Log.info("[DEBUG] \(tag): \(text)")
    }
}

@MainActor
final class DebugWindowController: NSWindowController {
    static let shared = DebugWindowController()

    private let textView: NSTextView
    private let formatter: DateFormatter

    private init() {
        let scroll = NSTextView.scrollableTextView()
        textView = scroll.documentView as! NSTextView
        textView.isEditable = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)

        formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ReadMe Debug"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.contentView = scroll
        super.init(window: window)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func append(_ tag: String, _ text: String) {
        let stamp = formatter.string(from: Date())
        let entry = "\(stamp) ── \(tag) ──\n\(text)\n\n"
        textView.textStorage?.append(NSAttributedString(
            string: entry,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.labelColor,
            ]
        ))
        textView.scrollToEndOfDocument(nil)
    }
}
