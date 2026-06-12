import AppKit
import SwiftUI

// The Logs panel of the main app window: a live tail of today's log file.
// Log.didAppend drives refreshes, so nothing polls the disk while idle.
struct LogViewerView: View {
    @State private var text = ""

    private let displayCap = 1_000_000 // show at most the last 1 MB

    var body: some View {
        VStack(spacing: 0) {
            LogTextView(text: text)
            Divider()
            HStack {
                Text(Log.shared.fileURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([Log.shared.fileURL])
                }
                Button("Clear") {
                    Log.clear()
                }
            }
            .padding(10)
        }
        .onAppear(perform: reload)
        .onReceive(
            NotificationCenter.default.publisher(for: Log.didAppend)
                .receive(on: DispatchQueue.main)
        ) { _ in
            reload()
        }
    }

    private func reload() {
        guard let data = try? Data(contentsOf: Log.shared.fileURL) else {
            text = "No log entries today."
            return
        }
        let tail = data.count > displayCap ? Data(data.suffix(displayCap)) : data
        text = String(decoding: tail, as: UTF8.self)
    }
}

// NSTextView keeps large logs scrollable and selectable without the cost of
// re laying out a giant SwiftUI Text on every append.
private struct LogTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let textView = scroll.documentView as! NSTextView
        textView.isEditable = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let textView = scroll.documentView as! NSTextView
        guard textView.string != text else { return }
        // Stick to the bottom only when the user is already there, so
        // scrolling back through history survives new appends.
        let visible = scroll.contentView.bounds
        let wasAtEnd = visible.maxY >= textView.frame.height - 40
        textView.textStorage?.setAttributedString(NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.labelColor,
            ]
        ))
        if wasAtEnd {
            textView.scrollToEndOfDocument(nil)
        }
    }
}
