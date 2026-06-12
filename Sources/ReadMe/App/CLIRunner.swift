import AppKit
import AVFoundation
import MLXAudioTTS
import ReadMeCore

// Command line interface, same binary as the app:
//   readme -t "text to read"          speak text aloud
//   readme -f notes.txt               speak file contents aloud
//   readme -t "text" -o out.m4a       render audio to a file instead
//   readme -f notes.txt -o out.wav    format inferred from extension
//   --output-type m4a|wav             explicit format (default m4a)
@MainActor
enum CLIRunner {
    static func handleIfNeeded(speech: SpeechController) -> Bool {
        let args = CommandLine.arguments

        if args.contains("-h") || args.contains("--help") {
            print(usage)
            exit(0)
        }

        var text: String?
        if let value = value(after: "-t", in: args) {
            text = value
        } else if let path = value(after: "-f", in: args) {
            guard let contents = try? String(contentsOfFile: (path as NSString).expandingTildeInPath, encoding: .utf8) else {
                fail("cannot read file: \(path)")
            }
            text = contents
        } else if let value = value(after: "--speak", in: args) {
            // Legacy debug flag, same as -t.
            text = value
        }

        guard let text else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            fail("nothing to read")
        }

        if let outputPath = value(after: "-o", in: args) {
            let url = URL(fileURLWithPath: (outputPath as NSString).expandingTildeInPath)
            let format = outputFormat(args: args, url: url)
            Task {
                do {
                    let seconds = try await AudioFileRenderer.render(text: trimmed, to: url, format: format)
                    print("wrote \(url.path) (\(String(format: "%.1f", seconds))s of audio)")
                    exit(0)
                } catch {
                    fail("render failed: \(error.localizedDescription)")
                }
            }
            return true
        }

        // Speak aloud and quit when playback finishes.
        var spoke = false
        speech.onStatusChange = { status in
            if status == .speaking {
                spoke = true
            }
            if status == .idle && spoke {
                exit(0)
            }
        }
        Task {
            await EngineManager.shared.warmUp(Preferences.engine)
            if Preferences.aiScriptEnabled {
                await ScriptPreparer.shared.warmUp()
            }
            speech.read(trimmed)
        }
        return true
    }

    private static let usage = """
    readme, local text to speech reader

    usage:
      readme -t "text to read"             speak text
      readme -f file.txt                   speak file contents
      readme -t "text" -o out.m4a          write audio file instead of playing
      readme --output-type m4a|wav         output format (default m4a,
                                           inferred from -o extension)
    """

    private static func value(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), args.count > index + 1 else { return nil }
        return args[index + 1]
    }

    private static func outputFormat(args: [String], url: URL) -> AudioFileRenderer.Format {
        let explicit = value(after: "--output-type", in: args)?.lowercased()
        let chosen = explicit ?? url.pathExtension.lowercased()
        switch chosen {
        case "wav":
            return .wav
        case "m4a", "":
            return .m4a
        default:
            fail("unsupported output type: \(chosen). Use m4a (small, portable) or wav (lossless).")
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("readme: \(message)\n".utf8))
        exit(1)
    }
}

// Renders the full pipeline (normalize, segment, chunk, optional polish,
// silence pauses) into an audio file instead of the speakers.
enum AudioFileRenderer {
    enum Format {
        case m4a
        case wav

        static func wavSettings(sampleRate: Double) -> [String: Any] {
            [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ]
        }
    }

    // AAC goes through a temp WAV plus afconvert: AVAudioFile's direct AAC
    // writing fails with a CoreAudio !dat error, and afconvert ships with
    // macOS and is bulletproof.
    static func render(text: String, to url: URL, format: Format) async throws -> Double {
        switch format {
        case .wav:
            return try await renderWAV(text: text, to: url)
        case .m4a:
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("readme-render-\(ProcessInfo.processInfo.processIdentifier).wav")
            defer { try? FileManager.default.removeItem(at: temp) }
            let seconds = try await renderWAV(text: text, to: temp)
            let convert = Process()
            convert.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
            // 48 kbps is the ceiling AAC accepts for 24 kHz mono; higher
            // values fail with the CoreAudio !dat error.
            convert.arguments = ["-f", "m4af", "-d", "aac", "-b", "48000", temp.path, url.path]
            try convert.run()
            convert.waitUntilExit()
            guard convert.terminationStatus == 0 else {
                throw NSError(domain: "ReadMe", code: 4, userInfo: [NSLocalizedDescriptionKey: "afconvert failed"])
            }
            return seconds
        }
    }

    private static func renderWAV(text: String, to url: URL) async throws -> Double {
        let kind = Preferences.engine
        let model = try await EngineManager.shared.model(for: kind)
        let sampleRate = Double(model.sampleRate)
        let polish = Preferences.aiScriptEnabled

        guard let bufferFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(domain: "ReadMe", code: 2, userInfo: [NSLocalizedDescriptionKey: "bad audio format"])
        }
        let file = try AVAudioFile(
            forWriting: url,
            settings: Format.wavSettings(sampleRate: sampleRate),
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        var totalFrames = 0
        func write(_ samples: [Float]) throws {
            guard !samples.isEmpty,
                  let buffer = AVAudioPCMBuffer(
                      pcmFormat: bufferFormat,
                      frameCapacity: AVAudioFrameCount(samples.count)
                  ),
                  let channel = buffer.floatChannelData?[0]
            else { return }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { pointer in
                channel.update(from: pointer.baseAddress!, count: samples.count)
            }
            try file.write(from: buffer)
            totalFrames += samples.count
        }

        let segments = TextSegmenter.segments(of: text)
        var chunkNumber = 0
        for (segmentIndex, segment) in segments.enumerated() {
            var pieces = SentenceChunker.chunks(for: TextNormalizer.normalize(segment))
            guard !pieces.isEmpty else { continue }
            if segmentIndex + 1 < segments.count, let last = pieces.last {
                pieces[pieces.count - 1] = SpeechChunk(
                    text: last.text,
                    pauseAfter: SentenceChunker.paragraphPause
                )
            }
            for piece in pieces {
                chunkNumber += 1
                let spokenText = polish
                    ? await ScriptPreparer.shared.prepare(piece.text)
                    : piece.text
                FileHandle.standardError.write(Data("rendering chunk \(chunkNumber)...\n".utf8))
                let stream = model.generateSamplesStream(
                    text: spokenText,
                    voice: Preferences.voice.isEmpty ? kind.defaultVoice : Preferences.voice,
                    refAudio: nil,
                    refText: nil,
                    language: nil,
                    generationParameters: nil,
                    streamingInterval: 1.0
                )
                for try await samples in stream {
                    try write(samples)
                }
                if piece.pauseAfter > 0 {
                    try write([Float](repeating: 0, count: Int(piece.pauseAfter * sampleRate)))
                }
            }
        }
        guard totalFrames > 0 else {
            throw NSError(domain: "ReadMe", code: 3, userInfo: [NSLocalizedDescriptionKey: "nothing readable in the input"])
        }
        return Double(totalFrames) / sampleRate
    }
}
