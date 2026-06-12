import ReadMeCore
import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let speech: SpeechController

    private var readItem: NSMenuItem!
    private var stopItem: NSMenuItem!
    private var debugItem: NSMenuItem!

    private let transportRow = TransportRowView()

    private var menu: NSMenu!

    private lazy var spinner: NSProgressIndicator = {
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false
        return spinner
    }()

    init(speech: SpeechController) {
        self.speech = speech
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        item.button?.image = Self.icon("waveform.circle")
        menu = buildMenu()
        menu.delegate = self

        // Left click opens the menu. Right click acts immediately: start
        // reading when idle, pause and resume while active.
        if let button = item.button {
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        speech.onStatusChange = { [weak self] status in
            self?.update(for: status)
        }
        speech.onNotice = { [weak self] message in
            guard let self else { return }
            StatusFeedback.shared.show(message, near: self.item.button)
        }
        update(for: .idle)
    }

    private var lastClick = Date.distantPast

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        Log.info("status item click: type=\(String(describing: event?.type.rawValue)) right=\(isRightClick) status=\(speech.status)")
        guard isRightClick else {
            showMenu()
            return
        }
        // A fast second click (accidental double click) would cancel the
        // read that the first click just started. Swallow it.
        let now = Date()
        guard now.timeIntervalSince(lastClick) > 0.35 else {
            Log.info("click ignored: double click debounce")
            return
        }
        lastClick = now
        switch speech.status {
        case .idle:
            speech.readSelection()
        case .speaking, .paused:
            speech.togglePause()
        case .loadingModel:
            // Click while the model loads cancels the read.
            speech.stop()
        }
    }

    private func showMenu() {
        guard let button = item.button else { return }
        // popUp delivers item actions reliably; the performClick plus
        // temporary item.menu hack lost actions (visible in the logs as
        // right clicks with no following action).
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.height + 4),
            in: button
        )
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        readItem = menu.addItem(
            withTitle: "Read Selection",
            action: #selector(readSelection),
            keyEquivalent: "r"
        )
        readItem.keyEquivalentModifierMask = [.command, .option]
        readItem.target = self

        transportRow.onBack = { [weak self] in self?.seekBack() }
        transportRow.onPlayPause = { [weak self] in self?.togglePause() }
        transportRow.onForward = { [weak self] in self?.seekForward() }
        let transportItem = NSMenuItem()
        transportItem.view = transportRow
        menu.addItem(transportItem)

        stopItem = menu.addItem(
            withTitle: "Stop",
            action: #selector(stopReading),
            keyEquivalent: ""
        )
        stopItem.target = self

        menu.addItem(.separator())

        let prefsItem = menu.addItem(
            withTitle: "Preferences…",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        prefsItem.target = self

        let logsItem = menu.addItem(
            withTitle: "Open Logs",
            action: #selector(openLogs),
            keyEquivalent: ""
        )
        logsItem.target = self

        debugItem = menu.addItem(
            withTitle: "Debug Mode",
            action: #selector(toggleDebugMode),
            keyEquivalent: ""
        )
        debugItem.target = self
        debugItem.state = Preferences.debugMode ? .on : .off

        menu.addItem(.separator())

        let quitItem = menu.addItem(
            withTitle: "Quit ReadMe",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp

        return menu
    }

    @objc private func openPreferences() {
        Log.info("menu: open preferences")
        PreferencesWindowController.shared.show()
    }

    @objc private func openLogs() {
        Log.info("menu: open logs")
        NSWorkspace.shared.activateFileViewerSelecting([Log.shared.fileURL])
    }

    @objc private func toggleDebugMode() {
        Preferences.debugMode.toggle()
        debugItem.state = Preferences.debugMode ? .on : .off
        Log.info("menu: debug mode \(Preferences.debugMode ? "on" : "off")")
        if Preferences.debugMode {
            DebugWindowController.shared.show()
            DebugTrace.append("polish system prompt", ScriptPreparer.instructions)
        } else {
            DebugWindowController.shared.window?.orderOut(nil)
        }
    }

    // MARK: - Actions

    @objc private func readSelection() {
        Log.info("menu: read selection")
        speech.readSelection()
    }

    @objc private func togglePause() {
        Log.info("menu: play pause")
        // Remote semantics: play when idle starts reading the selection.
        if speech.status == .idle {
            speech.readSelection()
        } else {
            speech.togglePause()
        }
    }

    @objc private func stopReading() {
        Log.info("menu: stop")
        speech.stop()
    }

    @objc private func seekBack() {
        Log.info("menu: back 5")
        speech.seekBack()
    }

    @objc private func seekForward() {
        Log.info("menu: forward 5")
        speech.seekForward()
    }

    // MARK: - State

    private func update(for status: SpeechController.Status) {
        if status == .loadingModel {
            showSpinner()
        } else {
            hideSpinner()
        }
        switch status {
        case .idle:
            item.button?.image = Self.icon("waveform.circle")
            transportRow.setState(playing: false, transportEnabled: false, playEnabled: true)
            stopItem.isEnabled = false
            readItem.isEnabled = true
        case .loadingModel:
            transportRow.setState(playing: false, transportEnabled: false, playEnabled: false)
            stopItem.isEnabled = true
            readItem.isEnabled = true
        case .speaking:
            item.button?.image = Self.icon("waveform.circle.fill")
            transportRow.setState(playing: true, transportEnabled: true, playEnabled: true)
            stopItem.isEnabled = true
            readItem.isEnabled = true
        case .paused:
            item.button?.image = Self.icon("pause.circle.fill")
            transportRow.setState(playing: false, transportEnabled: true, playEnabled: true)
            stopItem.isEnabled = true
            readItem.isEnabled = true
        }
    }

    // A real spinning NSProgressIndicator inside the status button while the
    // model loads, in place of the static icon.
    private func showSpinner() {
        guard let button = item.button else { return }
        if spinner.superview == nil {
            button.addSubview(spinner)
        }
        let size: CGFloat = 16
        spinner.frame = NSRect(
            x: (button.bounds.width - size) / 2,
            y: (button.bounds.height - size) / 2,
            width: size,
            height: size
        )
        spinner.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        button.image = nil
        spinner.startAnimation(nil)
    }

    private func hideSpinner() {
        guard spinner.superview != nil else { return }
        spinner.stopAnimation(nil)
        spinner.removeFromSuperview()
    }

    private static func icon(_ symbolName: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "ReadMe")
        image?.isTemplate = true
        return image
    }
}
