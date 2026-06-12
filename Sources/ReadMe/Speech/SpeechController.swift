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
    private var readSignature: String?

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
        readSignature = SelectionSignature.make(text)
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

                // Large selections normalize and chunk incrementally: a small
                // first segment (split at a paragraph boundary, which no
                // normalizer rule crosses) starts speech almost immediately
                // and later segments are processed while audio plays. The up
                // front pass cost 600 ms on a 300 KB selection when measured.
                let segments = TextSegmenter.segments(of: text)
                Log.info("read: \(segments.count) segments")

                let polish = Preferences.aiScriptEnabled
                let readStart = Date()
                var firstAudioLogged = false
                var globalIndex = 0

                // The LLM polish for chunk N+1 runs after chunk N finishes
                // generating, while N plays, so it never competes with TTS
                // generation for the GPU. The first chunk skips the polish
                // to keep the instant start.
                var nextPolish: Task<String, Never>?

                for (segmentIndex, segment) in segments.enumerated() {
                    try Task.checkCancellation()
                    var pieces = SentenceChunker.chunks(for: TextNormalizer.normalize(segment))
                    guard !pieces.isEmpty else { continue }
                    // The chunker zeroes the trailing pause; a segment
                    // boundary mid selection is still a paragraph break.
                    if segmentIndex + 1 < segments.count, let last = pieces.last {
                        pieces[pieces.count - 1] = SpeechChunk(
                            text: last.text,
                            pauseAfter: SentenceChunker.paragraphPause
                        )
                    }
                    Log.info("read: segment \(segmentIndex + 1)/\(segments.count), \(pieces.count) chunks")

                    for (pieceIndex, piece) in pieces.enumerated() {
                        try Task.checkCancellation()
                        let index = globalIndex
                        globalIndex += 1

                        let spokenText: String
                        if let pending = nextPolish {
                            spokenText = await pending.value
                            nextPolish = nil
                        } else {
                            spokenText = polish && index > 0
                                ? await ScriptPreparer.shared.prepare(piece.text)
                                : piece.text
                        }

                        DebugTrace.append("TTS chunk \(index + 1), pause \(piece.pauseAfter)s", spokenText)

                        // A fine streaming interval on the first chunk
                        // minimizes time to first audio; later chunks use a
                        // coarse interval for throughput since playback is
                        // already running.
                        let stream = model.generateSamplesStream(
                            text: spokenText,
                            voice: Preferences.voice.isEmpty ? kind.defaultVoice : Preferences.voice,
                            refAudio: nil,
                            refText: nil,
                            language: nil,
                            generationParameters: nil,
                            streamingInterval: index == 0 ? 0.2 : 1.0
                        )
                        for try await samples in stream {
                            try Task.checkCancellation()
                            if !firstAudioLogged {
                                firstAudioLogged = true
                                let ms = Int(Date().timeIntervalSince(readStart) * 1000)
                                Log.info("read: first audio after \(ms) ms")
                            }
                            player.append(samples)
                        }

                        // Prefetch the polish for the next chunk in this
                        // segment now that the GPU is free; it runs while
                        // this chunk's audio plays.
                        if polish, pieceIndex + 1 < pieces.count {
                            let upcoming = pieces[pieceIndex + 1].text
                            nextPolish = Task {
                                await ScriptPreparer.shared.prepare(upcoming)
                            }
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
                }

                guard globalIndex > 0 else {
                    // Selection had no speakable content (symbols only).
                    self.player = nil
                    self.status = .idle
                    NSSound.beep()
                    self.onNotice?("Nothing readable in the selection")
                    return
                }
                player.finishAppending()
                Log.info("read: generation complete, \(globalIndex) chunks")
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
