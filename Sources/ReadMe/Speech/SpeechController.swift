import ReadMeCore
import AppKit
import MLXAudioTTS
import UniformTypeIdentifiers

// Orchestrates the whole read flow: capture text, stream generation from the
// selected engine, and feed the streaming player. Generation runs ahead of
// playback so audio starts after the first chunk and continues seamlessly.
@MainActor
final class SpeechController {
    enum Status: Equatable {
        case idle
        case loadingModel
        case speaking
        case paused
    }

    var onStatusChange: ((Status) -> Void)?

    // Short human feedback for every user action, shown as a HUD under the
    // status item.
    var onNotice: ((String) -> Void)?

    private(set) var status: Status = .idle {
        didSet {
            if status != oldValue {
                onStatusChange?(status)
            }
        }
    }

    private var player: StreamingPlayer?
    private var generationTask: Task<Void, Never>?
    private var readSignature: String?
    private(set) var lastReadText: String?

    // Sample offsets where each spoken chunk starts, for sentence skip.
    // Filled on the main actor as generation progresses.
    private var chunkBoundaries: [Int] = []
    private var sampleRate = 24000

    private var sleepTimer: Timer?
    private(set) var sleepMinutesRemaining: Int?

    init() {
        // Speed changes in Settings apply to the current read immediately.
        NotificationCenter.default.addObserver(
            forName: Preferences.rateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.player?.setRate(Float(Preferences.speechRate))
            }
        }
    }

    // Playback position for the transport row time display.
    var playbackTime: (played: Double, buffered: Double)? {
        guard let player else { return nil }
        return (player.currentTime, player.bufferedTime)
    }

    // MARK: - Commands

    func readSelection() {
        // Without the Accessibility permission neither the AX read nor the
        // Cmd C fallback can see the selection. macOS also silently revokes
        // the permission whenever the app is rebuilt (the ad hoc signature
        // changes), so explain instead of just beeping.
        Log.info("readSelection: trusted=\(SelectionReader.isTrusted) status=\(status)")
        guard SelectionReader.isTrusted else {
            explainAccessibility()
            return
        }
        guard let raw = SelectionReader.currentSelection() else {
            NSSound.beep()
            onNotice?("Could not read the selection")
            return
        }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            NSSound.beep()
            onNotice?("No text selected")
            return
        }
        onNotice?("Reading selection")
        read(text)
    }

    // Reads whatever is on the clipboard, no selection or Accessibility
    // permission needed. Prefers the HTML flavor so web copies keep their
    // structure, same as browser selection capture.
    func readClipboard() {
        let pasteboard = NSPasteboard.general
        var text: String?
        if let html = pasteboard.string(forType: .html) {
            let extracted = HTMLTextExtractor.text(fromHTML: html)
            if !extracted.isEmpty {
                text = extracted
            }
        }
        if text == nil {
            text = pasteboard.string(forType: .string)
        }
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            NSSound.beep()
            onNotice?("Clipboard has no text")
            return
        }
        Log.info("readClipboard: \(text.count) chars")
        onNotice?("Reading clipboard")
        read(text)
    }

    // Re-renders the last read text into an audio file. Generation happens
    // fresh (the player's samples are gone once playback ends), reusing the
    // CLI's tested render path.
    func exportLastRead() {
        guard let text = lastReadText else {
            NSSound.beep()
            onNotice?("Nothing read yet")
            return
        }
        guard status == .idle else {
            onNotice?("Wait for the current read to finish")
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Audio, .wav]
        panel.nameFieldStringValue = "ReadMe Audio.m4a"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        onNotice?("Exporting audio")
        Task { [weak self] in
            do {
                let format: AudioFileRenderer.Format =
                    url.pathExtension.lowercased() == "wav" ? .wav : .m4a
                let seconds = try await AudioFileRenderer.render(text: text, to: url, format: format)
                Log.info("export: \(Int(seconds))s to \(url.lastPathComponent)")
                self?.onNotice?("Exported \(Int(seconds)) seconds of audio")
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                Log.error("export failed: \(error)")
                NSSound.beep()
                self?.onNotice?("Export failed")
            }
        }
    }

    func read(_ text: String) {
        stopPlayback()
        lastReadText = text
        chunkBoundaries = []
        readSignature = SelectionSignature.make(text)
        let kind = Preferences.engine
        Log.info("read: \(text.count) chars, engine=\(kind.rawValue), voice=\(Preferences.voice), polish=\(Preferences.aiScriptEnabled)")
        status = .loadingModel

        generationTask = Task { [weak self] in
            do {
                let model = try await EngineManager.shared.model(for: kind)
                try Task.checkCancellation()

                let player = try StreamingPlayer(
                    sampleRate: model.sampleRate,
                    rate: Float(Preferences.speechRate)
                )
                guard let self else { return }
                self.player = player
                player.onStateChange = { [weak self] state in
                    self?.playerStateChanged(state)
                }

                let readStart = Date()
                var firstAudioLogged = false

                self.sampleRate = model.sampleRate
                let chunkCount = try await SpeechPipeline.run(
                    text: text,
                    model: model,
                    options: SpeechPipeline.Options(
                        polishFirstChunk: false,
                        fastFirstChunk: true
                    ),
                    onChunkStart: { offset in
                        self.chunkBoundaries.append(offset)
                    }
                ) { samples in
                    if !firstAudioLogged {
                        firstAudioLogged = true
                        let ms = Int(Date().timeIntervalSince(readStart) * 1000)
                        Log.info("read: first audio after \(ms) ms")
                    }
                    player.append(samples)
                }

                guard chunkCount > 0 else {
                    // Selection had no speakable content (symbols only).
                    self.player = nil
                    self.status = .idle
                    NSSound.beep()
                    self.onNotice?("Nothing readable in the selection")
                    return
                }
                player.finishAppending()
                Log.info("read: generation complete, \(chunkCount) chunks")
            } catch is CancellationError {
                Log.info("read: cancelled")
            } catch {
                Log.error("read: generation failed: \(error)")
                self?.fail(error)
            }
        }
    }

    func stop() {
        let wasActive = status != .idle
        stopPlayback()
        if wasActive {
            onNotice?("Stopped")
        }
    }

    func togglePause() {
        guard player != nil else {
            onNotice?("Nothing playing")
            return
        }
        if status == .paused {
            // If the selection changed while paused, resuming the old audio
            // would read stale text. Restart with the new selection instead.
            if let changed = changedSelection() {
                Log.info("resume: selection changed, restarting")
                onNotice?("New selection, reading")
                read(changed)
                return
            }
            onNotice?("Resumed")
        } else {
            onNotice?("Paused")
        }
        player?.togglePause()
    }

    // AX only check, costs about a millisecond. Returns the new selection
    // when its head and tail signature differs from what is being read; nil
    // when unchanged, empty, or unreadable (then resume is correct).
    private func changedSelection() -> String? {
        guard SelectionReader.isTrusted,
              let raw = SelectionReader.quickSelection()
        else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return SelectionSignature.make(text) != readSignature ? text : nil
    }

    func seekBack() {
        guard player != nil else {
            onNotice?("Nothing playing")
            return
        }
        onNotice?("Back 5 seconds")
        player?.seek(bySeconds: -5)
    }

    func seekForward() {
        guard player != nil else {
            onNotice?("Nothing playing")
            return
        }
        onNotice?("Forward 5 seconds")
        player?.seek(bySeconds: 5)
    }

    // Sentence skip rides the chunk boundaries recorded during generation.
    // Back inside the first second of a sentence goes to the previous one;
    // deeper in, it restarts the current sentence, media player style.
    func skipForwardSentence() {
        guard let player, !chunkBoundaries.isEmpty else {
            onNotice?("Nothing playing")
            return
        }
        let played = player.currentSample
        guard let next = chunkBoundaries.first(where: { $0 > played }) else {
            onNotice?("At the last sentence")
            return
        }
        onNotice?("Next sentence")
        player.seek(toSample: next)
    }

    func skipBackSentence() {
        guard let player, !chunkBoundaries.isEmpty else {
            onNotice?("Nothing playing")
            return
        }
        let played = player.currentSample
        let grace = sampleRate
        let current = chunkBoundaries.last(where: { $0 <= played }) ?? 0
        let target: Int
        if played - current < grace {
            target = chunkBoundaries.last(where: { $0 < current }) ?? 0
        } else {
            target = current
        }
        onNotice?("Previous sentence")
        player.seek(toSample: target)
    }

    // MARK: - Sleep timer

    func setSleepTimer(minutes: Int?) {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepMinutesRemaining = minutes
        guard let minutes else {
            onNotice?("Sleep timer off")
            return
        }
        onNotice?("Stopping in \(minutes) minutes")
        Log.info("sleep timer: \(minutes) minutes")
        let timer = Timer(timeInterval: Double(minutes) * 60, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.sleepMinutesRemaining = nil
                self.sleepTimer = nil
                if self.status != .idle {
                    Log.info("sleep timer: fired, stopping")
                    self.stop()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        sleepTimer = timer
    }

    // Tears down playback without user feedback; read() uses this when
    // replacing the current read.
    private func stopPlayback() {
        generationTask?.cancel()
        generationTask = nil
        if let player {
            player.onStateChange = nil
            player.stop()
        }
        player = nil
        status = .idle
    }

    // MARK: - Internals

    private func playerStateChanged(_ state: StreamingPlayer.State) {
        switch state {
        case .playing:
            status = .speaking
        case .paused:
            status = .paused
        case .finished:
            player = nil
            generationTask = nil
            status = .idle
        case .stopped:
            break
        }
    }

    private func explainAccessibility() {
        // Clear stale rows from older signatures so Settings shows the truth.
        SelectionReader.resetStalePermission()
        let alert = NSAlert()
        alert.messageText = "ReadMe needs Accessibility permission"
        alert.informativeText = "ReadMe reads the selected text through the Accessibility API. "
            + "Enable ReadMe under Privacy and Security, Accessibility. "
            + "If it is already listed, toggle it off and on again. macOS resets the permission whenever the app is rebuilt."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            SelectionReader.openAccessibilitySettings()
        }
    }

    private func fail(_ error: Error) {
        Log.error("generation failed: \(error)")
        player?.stop()
        player = nil
        status = .idle
        let alert = NSAlert()
        alert.messageText = "ReadMe could not generate speech"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
