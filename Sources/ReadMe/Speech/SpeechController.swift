import ReadMeCore
import AppKit
import MLXAudioTTS

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

    func read(_ text: String) {
        stopPlayback()
        let kind = Preferences.engine
        Log.info("read: \(text.count) chars, engine=\(kind.rawValue), voice=\(Preferences.voice), polish=\(Preferences.aiScriptEnabled)")
        status = .loadingModel

        generationTask = Task { [weak self] in
            do {
                let model = try await EngineManager.shared.model(for: kind)
                try Task.checkCancellation()

                let player = try StreamingPlayer(sampleRate: model.sampleRate)
                guard let self else { return }
                self.player = player
                player.onStateChange = { [weak self] state in
                    self?.playerStateChanged(state)
                }

                // Normalize symbols into spoken forms, then chunk to stay
                // under the engine's per call audio limit.
                let pieces = SentenceChunker.chunks(for: TextNormalizer.normalize(text))
                Log.info("read: \(pieces.count) chunks")
                guard !pieces.isEmpty else {
                    // Selection had no speakable content (symbols only).
                    self.player = nil
                    self.status = .idle
                    NSSound.beep()
                    self.onNotice?("Nothing readable in the selection")
                    return
                }
                let polish = Preferences.aiScriptEnabled

                // The LLM polish for chunk N+1 runs while chunk N is being
                // generated and played, so its latency stays hidden. The very
                // first chunk skips the polish to keep the instant start.
                var nextPolish: Task<String, Never>?

                for (index, piece) in pieces.enumerated() {
                    try Task.checkCancellation()
                    let spokenText: String
                    if let pending = nextPolish {
                        spokenText = await pending.value
                    } else {
                        spokenText = piece.text
                    }
                    if polish, index + 1 < pieces.count {
                        let upcoming = pieces[index + 1].text
                        nextPolish = Task {
                            await ScriptPreparer.shared.prepare(upcoming)
                        }
                    } else {
                        nextPolish = nil
                    }

                    let stream = model.generateSamplesStream(
                        text: spokenText,
                        voice: Preferences.voice.isEmpty ? kind.defaultVoice : Preferences.voice,
                        refAudio: nil,
                        refText: nil,
                        language: nil,
                        generationParameters: nil,
                        streamingInterval: 0.5
                    )
                    for try await samples in stream {
                        try Task.checkCancellation()
                        player.append(samples)
                    }
                    // The model never sees line or paragraph breaks, so
                    // structural pauses are injected as real silence.
                    if piece.pauseAfter > 0 {
                        let silence = [Float](
                            repeating: 0,
                            count: Int(piece.pauseAfter * Double(model.sampleRate))
                        )
                        player.append(silence)
                    }
                }
                player.finishAppending()
                Log.info("read: generation complete")
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
        onNotice?(status == .paused ? "Resumed" : "Paused")
        player?.togglePause()
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
