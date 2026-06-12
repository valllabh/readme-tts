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
    private let timeLabel = NSTextField(labelWithString: "")

    init() {
        backButton = Self.button(symbol: "gobackward.5", pointSize: 16)
        playPauseButton = Self.button(symbol: "play.fill", pointSize: 24)
        forwardButton = Self.button(symbol: "goforward.5", pointSize: 16)
        stopButton = Self.button(symbol: "stop.fill", pointSize: 24)
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 58))

        backButton.target = self
        backButton.action = #selector(backTapped)
        playPauseButton.target = self
        playPauseButton.action = #selector(playPauseTapped)
        forwardButton.target = self
        forwardButton.action = #selector(forwardTapped)
        stopButton.target = self
        stopButton.action = #selector(stopTapped)

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.alignment = .center

        let buttons = NSStackView(views: [backButton, playPauseButton, stopButton, forwardButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 22

        let column = NSStackView(views: [buttons, timeLabel])
        column.orientation = .vertical
        column.alignment = .centerX
        column.spacing = 2
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.centerXAnchor.constraint(equalTo: centerXAnchor),
            column.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    // Position through generated-so-far; total grows while generation runs.
    func setTime(played: Double, buffered: Double) {
        timeLabel.stringValue = "\(Self.clock(played)) / \(Self.clock(buffered))"
    }

    func clearTime() {
        timeLabel.stringValue = ""
    }

    private static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
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
