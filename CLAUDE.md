# ReadMe

macOS menu bar app that reads selected text aloud with local MLX text to speech. Pure Swift, no Python.

## Build

Use the Makefile: `make build`, `make run`, `make release`, `make bundle`, `make install`. Plain SwiftPM works from CommandLineTools, full Xcode is not required (mlx-swift ships precompiled Metal shaders).

## Key facts

- MLX needs mlx.metallib next to the binary at runtime. CommandLineTools cannot compile Metal shaders, so the Makefile copies the prebuilt one from the Python mlx wheel (pip3 install mlx, keep 0.31.x to match mlx-swift). Without it the app aborts with "Failed to load the default metallib".
- No XCTest or Swift Testing under CommandLineTools. Tests live in Sources/ReadMeSelfTest as a plain executable with assertions, run via make test.
- Pure logic (chunker, engine catalog, preferences) lives in the ReadMeCore library target so the self test can import it.

- Engine: Marvis only (native streaming, 60 s audio cap per call, aborts on overlong input, ignores newlines, trained on speech transcripts so digits and symbols hallucinate). Via mlx-audio-swift `TTS.loadModel`, pinned to branch main.
- Script prep: TextNormalizer (regex rules from coqui/misaki/NeMo plus NumberFormatter spellOut) always runs; ScriptPreparer (Gemma 3 1B 4bit via mlx-swift-lm ChatSession) optionally polishes chunk N+1 while chunk N speaks. Chunk one never waits for the LLM.
- Pauses are injected silence (SpeechChunk.pauseAfter), not model behavior: 0.9 s paragraphs, 0.5 s lines and table rows, 0.15 s sentence gaps.
- Audio: 24 kHz mono float. StreamingPlayer keeps all samples for backward seek. Epoch counter guards stale AVAudioPlayerNode callbacks.
- Selection capture needs Accessibility permission. AX selected text first, pasteboard Cmd C fallback with snapshot and restore.
- Target uses Swift language mode v5 to avoid strict concurrency friction with non Sendable MLX types.
- Debug without UI: `.build/debug/ReadMe --speak "text"`.
- make install targets ~/Applications, not /Applications: VJ's account is not in the admin group. lsregister runs after copy so Spotlight finds the app.
- Shortcuts are stored per ShortcutAction in UserDefaults (Carbon keyCode plus modifiers); Preferences.shortcutsChanged notification triggers hotkey re registration.
- Bundles are signed with the local "ReadMe Dev Signing" certificate (login keychain), so the Accessibility permission survives rebuilds. The Makefile falls back to ad hoc if the cert is missing, which breaks the permission on every build.
- If the app launches untrusted it runs tccutil reset on its own bundle id before prompting (SelectionReader.resetStalePermission), so stale permission rows from older signatures never linger.
- Every user action emits a HUD notice under the status item (StatusFeedback). Keep that pattern for new actions; silent failures are not acceptable to VJ.
- Marvis voices: conversational_a is female (about 182 Hz), conversational_b is male (about 124 Hz), shown as Ava and Leo.
- docs/ARCHITECTURE.md has the design. Update it when structure changes.
