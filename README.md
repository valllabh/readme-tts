# ReadMe

A macOS menu bar app that reads any selected text aloud using expressive AI text to speech, running fully local on Apple Silicon via MLX. Audio starts streaming immediately and generation continues while playback runs.

## Features

- Reads the current text selection in any app
- Fully local inference, no network calls after the models download once
- Marvis TTS engine: token level streaming, audio starts almost instantly
- Reading script preparation in two stages
  - Programmatic normalizer: markdown, tables, URLs, emails, numbers, currency, times, ordinals, units, symbols, abbreviations all expand into spoken words
  - Optional AI Script Polish: a small local LLM (Gemma 3 1B on MLX) rewrites each chunk for natural reading, pipelined ahead of speech so it adds no wait
- Real pauses at structure: paragraph breaks, line breaks, list items, and table rows pause like a human reader (silence is injected, since the model ignores newlines)
- Transport controls: pause, resume, stop, seek 5 seconds back and forward
- Global hotkeys, all recordable in Preferences: Cmd Option R read selection, Cmd Option P pause and resume, Option Escape read or stop (the macOS Spoken Content shortcut, so the accessibility trigger drives ReadMe)
- Preferences window (Cmd comma from the menu): voice model and voice, AI Script Polish, shortcut recording, launch at login
- Services menu entry "Read with ReadMe" on right click (app bundle install)

## Requirements

- Apple Silicon Mac
- macOS 14 or later
- Command Line Tools with Swift 6 (no full Xcode needed)
- Python mlx package for the prebuilt Metal shader library: `pip3 install mlx`

MLX needs a compiled `mlx.metallib` at runtime and CommandLineTools cannot compile Metal shaders. The Makefile copies the prebuilt library from the Python mlx wheel next to the binary. The mlx version must stay in the same minor series as the mlx core embedded in mlx-swift (currently 0.31.x).

## Build and run

```
make build      # debug build
make run        # build and run from terminal
make release    # release build
make bundle     # build ReadMe.app under .build/
make install    # copy ReadMe.app to ~/Applications (Spotlight indexed)
make icon       # regenerate Assets/ReadMe.icns from scripts/makeicon.swift
```

First launch asks for Accessibility permission. This is required to read the selected text from other apps. The first read with each engine downloads the model from Hugging Face and caches it locally.

## Usage

1. Select text anywhere.
2. Press Cmd Option R, or right click the waveform icon in the menu bar.
3. While reading, right click the icon to pause and resume, or press Cmd Option P.
4. Left click the icon for the menu: a remote style transport row (back 5 seconds, play or pause, forward 5 seconds), stop, preferences, logs.
5. Resuming after the selection changed restarts with the new selection automatically.

Option Escape also starts reading, matching the macOS accessibility Speak Selection shortcut. Disable the system one under System Settings, Accessibility, Spoken Content so both do not speak at once.

AI Script Polish can be toggled in the right click menu. The first chunk always speaks immediately without waiting for the LLM.

## CLI

`make install` links the app binary to `/opt/homebrew/bin/readme`:

```
readme -t "text to read"        speak text
readme -f notes.txt             speak file contents
readme -t "text" -o out.m4a     write audio instead of playing
readme -f notes.txt -o out.wav  format inferred from extension
```

Two output formats: m4a (AAC, small, made for sending around) and wav (lossless).

## Documentation

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for design details.
