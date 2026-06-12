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
