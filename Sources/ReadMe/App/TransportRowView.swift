import AppKit

// Remote control style transport row for the status menu: back 5, play or
// pause in the center, forward 5. Lives in a menu item custom view so the
// menu stays open while seeking repeatedly.
@MainActor
final class TransportRowView: NSView {
    var onBack: (() -> Void)?
    var onPlayPause: (() -> Void)?
    var onForward: (() -> Void)?

    private let backButton: NSButton
    private let playPauseButton: NSButton
    private let forwardButton: NSButton

    init() {
        backButton = Self.button(symbol: "gobackward.5", pointSize: 16)
        playPauseButton = Self.button(symbol: "play.fill", pointSize: 24)
        forwardButton = Self.button(symbol: "goforward.5", pointSize: 16)
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 44))

        backButton.target = self
        backButton.action = #selector(backTapped)
        playPauseButton.target = self
        playPauseButton.action = #selector(playPauseTapped)
        forwardButton.target = self
        forwardButton.action = #selector(forwardTapped)

        let stack = NSStackView(views: [backButton, playPauseButton, forwardButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 28
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    func setState(playing: Bool, transportEnabled: Bool, playEnabled: Bool) {
        let config = NSImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        let symbol = playing ? "pause.fill" : "play.fill"
        playPauseButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol)?
            .withSymbolConfiguration(config)
        playPauseButton.isEnabled = playEnabled
        backButton.isEnabled = transportEnabled
        forwardButton.isEnabled = transportEnabled
    }

    @objc private func backTapped() {
        onBack?()
    }

    @objc private func playPauseTapped() {
        onPlayPause?()
    }

    @objc private func forwardTapped() {
        onForward?()
    }

    private static func button(symbol: String, pointSize: CGFloat) -> NSButton {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol)?
            .withSymbolConfiguration(config)
        let button = NSButton(image: image ?? NSImage(), target: nil, action: nil)
        button.isBordered = false
        button.imageScaling = .scaleNone
        return button
    }
}
