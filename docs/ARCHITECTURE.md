# Architecture

ReadMe is a pure Swift menu bar app. All inference runs in process through MLX via the mlx-audio-swift package. There is no helper server and no Python runtime.

## Components

```
Sources/ReadMeCore/    pure logic, fully testable: TextNormalizer, NumberSpeller,
                       SentenceChunker, TextSegmenter, SelectionSignature,
                       PolishValidator, Preferences
Sources/ReadMe/
  App/        entry point, app delegate, status bar controller, transport row
              view, preferences window, debug trace window, HUD feedback,
              services provider, CLI argument handling
  Selection/  reads the selected text from the frontmost app
  Hotkey/     global hotkeys via the Carbon hotkey API
  Speech/     SpeechPipeline (the single generate loop), EngineManager,
              ScriptPreparer (polish LLM), SpeechController (live playback
              orchestration), AudioFileRenderer (file output)
  Playback/   streaming audio player with pause and seek
  Support/    file logger
Sources/ReadMeSelfTest/  assert based tests for ReadMeCore, run via make test
scripts/makeicon.swift   regenerates Assets/ReadMe.icns (make icon)
```

Single responsibility map: SpeechPipeline is the one place the read pipeline
lives (segment, normalize, chunk, polish prefetch, generate, silence); its two
consumers differ only in the sample sink, the streaming player for live reads
and AVAudioFile for the CLI. Polish output validation is pure string logic in
ReadMeCore (PolishValidator) so every guard is unit tested.

## CLI

The app binary doubles as a CLI (symlinked to /opt/homebrew/bin/readme by
make install): readme -t "text" speaks, -f file speaks a file, -o out.m4a
renders to a file (m4a small and portable, wav lossless). CLI runs headless,
no permission prompts or status item.

### Preferences (App/PreferencesWindow.swift)

SwiftUI grouped form in an NSHostingController window, opened with Cmd comma from the status menu. Sections: launch at login (SMAppService), voice model and voice (driven by EngineKind.allCases and engine.voices so future models slot in), AI Script Polish, and shortcut recording. Shortcuts persist as Carbon keyCode plus modifiers in UserDefaults; recording captures the next keyDown via a local event monitor (plain Escape cancels). Saving posts Preferences.shortcutsChanged and AppDelegate re registers all hotkeys live. Install goes to ~/Applications because this account has no admin rights for /Applications; Spotlight indexes both.

CommandLineTools ships neither XCTest nor the Swift Testing module, so tests are a plain executable with assertions.

## Metal shader library

MLX loads a compiled `mlx.metallib` at runtime, searching next to the executable first. SwiftPM under CommandLineTools cannot compile Metal shaders, so the Makefile colocates the prebuilt library from the Python mlx wheel (`pip3 install mlx`). Keep the wheel in the same minor version series as the mlx core embedded in mlx-swift (0.31.x today). Without this file the app aborts at first generation with "Failed to load the default metallib".

## Model cache

Models download once into the Hugging Face cache under `~/.cache/huggingface/hub/mlx-audio/<org>_<repo>`. The upstream completeness check accepts any nonzero safetensors file, so an interrupted download can leave a broken snapshot that still passes. EngineManager recovers by purging the snapshot and retrying once when a load fails.

### Selection capture (Selection/SelectionReader.swift)

Two strategies, tried in order:

1. Accessibility API: read kAXSelectedTextAttribute from the focused UI element.
2. Pasteboard fallback: snapshot the pasteboard, synthesize Cmd C, wait for the change count to move, read the string, restore the snapshot.

Both need the Accessibility permission, requested on first launch.

### Engine (Speech/EngineManager.swift)

The voice is Marvis (Marvis-AI/marvis-tts-250m-v0.2-MLX-8bit), loaded through the unified `TTS.loadModel` entry point of mlx-audio-swift and kept warm in memory after first load. It preloads at app start. Marvis streams natively, emitting audio about every half second of generated speech, so playback starts almost immediately.

Marvis constraints that shape the pipeline: it caps each generation call at 60 seconds of audio, aborts on overlong inputs, splits internally only on newlines, and was trained on speech transcripts. Nothing in the model stack normalizes text, so digits, symbols, URLs, and markdown reach the tokenizer raw unless the app rewrites them.

### Script preparation (ReadMeCore + Speech/ScriptPreparer.swift)

Two stages run before any audio is generated:

1. TextNormalizer (programmatic, always on): markdown structure, tables (pipe and tab rows become comma separated cells per row), links and bare URLs, emails, times, currency, percent, units, ordinals, decimals, years, long digit strings, symbols, abbreviations, snake case. Number expansion uses NumberFormatter spellOut. Rules ported from coqui TTS cleaners, misaki, and NeMo categories.
2. AI Script Polish (optional, default on): Gemma 3 1B 4bit through mlx-swift-lm ChatSession rewrites each chunk for natural reading. The polish for chunk N+1 starts after chunk N finishes generating and runs while N plays, so it never competes with TTS generation for the GPU; chunk one always skips the polish to preserve the instant start. If the LLM is not loaded yet, text passes through unchanged.

## Speed

Time to first audio is the primary metric. The levers: both models preload and prime at app start (a tiny throwaway generation compiles the lazy Metal kernels, which otherwise cost seconds on the first real read); the first chunk streams at a 0.2 second interval for the earliest possible samples while later chunks use 1.0 second for throughput; the polish LLM only runs when the GPU is idle between chunk generations; the pasteboard fallback polls every 10 ms with a 300 ms cap. Every read logs "first audio after N ms" so regressions show up in the log.

### Chunking and pauses (Speech/SentenceChunker.swift)

The chunker returns SpeechChunk values: bounded text (500 character cap, sentence boundaries preferred, clause splits for giant sentences) plus a pauseAfter duration. Because the model never sees line or paragraph breaks, structural pauses are injected as real silence by the player: 0.9 s after paragraphs, 0.5 s after line breaks and list items and table rows, 0.15 s between sentence chunks inside a block. A line ending without punctuation followed by a lowercase line is treated as PDF style wrapping and joined instead of paused.

### Playback (Playback/StreamingPlayer.swift)

AVAudioEngine with a single AVAudioPlayerNode at the model sample rate (24 kHz mono float). All generated samples accumulate in a master buffer. The player schedules quarter second slices and keeps at most four in flight, which gives quarter second seek granularity and keeps transport actions responsive.

- Pause and resume map to node pause and play.
- Seek stops the node, moves the cursor in the master buffer, and reschedules. Backward seek always works because every generated sample is retained. Forward seek clamps to what has been generated so far.
- An epoch counter invalidates stale buffer completion callbacks after a seek or stop.

### Orchestration (Speech/SpeechController.swift)

A single state machine: idle, loadingModel, speaking, paused. A read cancels any active read, loads the engine if needed, then iterates generation chunks and appends samples to the player. The status bar icon mirrors the state.

## Entry points for reading

- Global hotkey Cmd Option R
- Option Escape (the macOS Spoken Content shortcut): read when idle, stop when active
- Right click on the status item (read when idle, pause and resume while active, cancel while loading); left click opens the menu with a remote style transport row
- Resume checks an AX only head and tail signature of the current selection (SelectionSignature) and restarts when the selection changed while paused
- Menu item Read Selection and the transport row play button (play when idle reads the selection)
- Services menu "Read with ReadMe" (declared in Bundle/Info.plist, active when installed as an app bundle)
- CLI debug flag: `ReadMe --speak "text"`
