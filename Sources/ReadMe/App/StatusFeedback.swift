import AppKit

// A small HUD that appears under the status item for a moment, so every
// action gives visible feedback even though the app has no windows.
@MainActor
final class StatusFeedback {
    static let shared = StatusFeedback()

    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(_ message: String, near button: NSStatusBarButton?) {
        hideTask?.cancel()
        panel?.orderOut(nil)
        panel = nil
        guard let button, let window = button.window else { return }

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        label.sizeToFit()

        let padX: CGFloat = 12
        let padY: CGFloat = 7
        let size = NSSize(
            width: label.frame.width + padX * 2,
            height: label.frame.height + padY * 2
        )

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 9
        effect.layer?.masksToBounds = true
        label.setFrameOrigin(NSPoint(x: padX, y: padY))
        effect.addSubview(label)

        let hud = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        hud.isOpaque = false
        hud.backgroundColor = .clear
        hud.level = .statusBar
        hud.hasShadow = true
        hud.ignoresMouseEvents = true
        hud.isReleasedWhenClosed = false
        hud.contentView = effect

        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = window.convertToScreen(buttonRect)
        var origin = NSPoint(
            x: screenRect.midX - size.width / 2,
            y: screenRect.minY - size.height - 6
        )
        if let screen = window.screen {
            origin.x = min(max(origin.x, screen.visibleFrame.minX + 8),
                           screen.visibleFrame.maxX - size.width - 8)
        }
        hud.setFrameOrigin(origin)
        hud.alphaValue = 1
        hud.orderFrontRegardless()
        panel = hud

        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0.3
            hud.animator().alphaValue = 0
            NSAnimationContext.endGrouping()
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            if self?.panel === hud {
                hud.orderOut(nil)
                self?.panel = nil
            }
        }
    }
}
