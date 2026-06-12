import AppKit

// Remote control style transport row for the status menu: back 5, then play
// or pause and stop in the center, forward 5. Lives in a menu item custom
// view so the menu stays open while seeking repeatedly.
@MainActor
final class TransportRowView: NSView {
    var onBack: (() -> Void)?
    var onPlayPause: (() -> Void)?
    var onForward: (() -> Void)?
    var onStop: (() -> Void)?

    private let backButton: NSButton
    private let playPauseButton: NSButton
    private let forwardButton: NSButton
    private let stopButton: NSButton

    init() {
        backButton = Self.button(symbol: "gobackward.5", pointSize: 16)
        playPauseButton = Self.button(symbol: "play.fill", pointSize: 24)
        forwardButton = Self.button(symbol: "goforward.5", pointSize: 16)
        stopButton = Self.button(symbol: "stop.fill", pointSize: 24)
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 44))

        backButton.target = self
        backButton.action = #selector(backTapped)
        playPauseButton.target = self
        playPauseButton.action = #selector(playPauseTapped)
        forwardButton.target = self
        forwardButton.action = #selector(forwardTapped)
        stopButton.target = self
        stopButton.action = #selector(stopTapped)

        let stack = NSStackView(views: [backButton, playPauseButton, stopButton, forwardButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 22
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

    func setState(playing: Bool, transportEnabled: Bool, playEnabled: Bool, stopEnabled: Bool) {
        let config = NSImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        let symbol = playing ? "pause.fill" : "play.fill"
        playPauseButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol)?
            .withSymbolConfiguration(config)
        playPauseButton.isEnabled = playEnabled
        backButton.isEnabled = transportEnabled
        forwardButton.isEnabled = transportEnabled
        stopButton.isEnabled = stopEnabled
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

    @objc private func stopTapped() {
        onStop?()
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
