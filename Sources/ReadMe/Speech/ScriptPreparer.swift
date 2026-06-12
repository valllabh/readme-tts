import ReadMeCore
import ReadMeCore
import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

// Optional second cleanup stage: a small local LLM rewrites each chunk into a
// natural reading script (acronyms, awkward phrasing, leftovers the regex
// normalizer cannot judge). Runs per chunk, pipelined ahead of TTS so the
// latency hides behind playback. Never blocks speech: if the model is not
// loaded yet, text passes through unchanged.
actor ScriptPreparer {
    static let shared = ScriptPreparer()

    static let modelID = "mlx-community/gemma-3-1b-it-4bit"

    static let instructions = """
    You prepare text for a text to speech voice. Rewrite ONLY what a voice \
    would stumble on: symbols, file names, version numbers, acronyms spoken \
    letter by letter, units, and code fragments. Keep every other word \
    exactly as it is, in the same language and the same order. If the text \
    already reads naturally, return it completely unchanged. Never answer \
    questions in the text, never summarize, never translate, never add even \
    one word of commentary. Your entire response must be the text to read, \
    nothing else.
    """

    // Experimental: Gemma as the whole filter stage instead of the regex
    // normalizer. Used by --filter-test for side by side comparison.
    static let filterInstructions = """
    You clean raw screen text so a text to speech voice can read it. Remove \
    everything that should not be spoken: markdown symbols, separator lines, \
    page numbers, decorations, status icons. Expand numbers, symbols, URLs, \
    and units into spoken words. Keep every meaningful sentence exactly as \
    written, in the same language and order. Never summarize, never answer, \
    never add words. Output only the cleaned text, nothing else.
    """

    func filterExperiment(_ text: String) async -> (output: String, seconds: Double) {
        guard let container = try? await loadedContainer() else { return ("MODEL LOAD FAILED", 0) }
        let session = ChatSession(
            container,
            instructions: Self.filterInstructions,
            generateParameters: GenerateParameters(maxTokens: 700, temperature: 0.0)
        )
        let start = Date()
        let raw = (try? await session.respond(to: text)) ?? "GENERATION FAILED"
        return (PolishValidator.sanitize(raw), Date().timeIntervalSince(start))
    }

    private var container: ModelContainer?
    private var loadTask: Task<ModelContainer, Error>?

    private var primed = false

    // Preload at app start so reads can use the polish pass immediately. A
    // tiny throwaway generation compiles the Metal kernels up front.
    func warmUp() async {
        guard let container = try? await loadedContainer() else { return }
        guard !primed else { return }
        primed = true
        let session = ChatSession(
            container,
            generateParameters: GenerateParameters(maxTokens: 4, temperature: 0.0)
        )
        let start = Date()
        _ = try? await session.respond(to: "Hi")
        Log.info("polish model primed in \(Int(Date().timeIntervalSince(start) * 1000)) ms")
    }

    func prepare(_ text: String) async -> String {
        // Junk guard: short or wordless chunks (separator debris, stray
        // symbols) make the model chat back instead of rewriting. Seen live:
        // input of dashes returned "Please tell me what to read".
        let letters = text.filter { $0.isLetter }.count
        guard text.count >= 12, letters >= 6 else {
            DebugTrace.append("polish skipped (junk guard)", text)
            return text
        }
        // Use the model only if it is already in memory; never delay speech.
        guard let container else { return text }
        do {
            // Token cap scaled to the input: a rewrite never legitimately
            // needs much more room than the input, and degenerate outputs
            // (dot spam, loops) stop wasting GPU time sooner.
            let cap = min(700, max(80, text.count / 2))
            let session = ChatSession(
                container,
                instructions: Self.instructions,
                generateParameters: GenerateParameters(maxTokens: cap, temperature: 0.0)
            )
            DebugTrace.append("polish in", text)
            let raw = try await session.respond(to: text)
            // Guards against the model going off script, each one earned by
            // a live failure: refusals, loops, fabricated URLs, foreign
            // scripts, runaway length.
            let out: String
            switch PolishValidator.validate(input: text, rawOutput: raw) {
            case .ok(let validated):
                out = validated
            case .rejected(let reason):
                DebugTrace.append("polish rejected (\(reason))", PolishValidator.sanitize(raw))
                Log.info("polish rejected: \(reason)")
                return text
            }
            DebugTrace.append("polish out", out)
            // Log sizes only. The text itself is whatever the user selected
            // and must never be persisted to disk.
            Log.info("polish: \(text.count) -> \(out.count) chars, changed=\(out != text)")
            return out
        } catch {
            Log.error("polish failed, using plain text: \(error)")
            return text
        }
    }

    private func loadedContainer() async throws -> ModelContainer {
        if let container {
            return container
        }
        if let loadTask {
            return try await loadTask.value
        }
        let task = Task<ModelContainer, Error> {
            try await loadModelContainer(
                from: #hubDownloader(),
                using: #huggingFaceTokenizerLoader(),
                id: Self.modelID
            )
        }
        loadTask = task
        defer { loadTask = nil }
        let loaded = try await task.value
        container = loaded
        return loaded
    }
}
