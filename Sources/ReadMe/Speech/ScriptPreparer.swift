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
            let session = ChatSession(
                container,
                instructions: Self.instructions,
                generateParameters: GenerateParameters(maxTokens: 700, temperature: 0.0)
            )
            DebugTrace.append("polish in", text)
            let raw = try await session.respond(to: text)
            let out = Self.sanitize(raw)
            // Guards against the model going off script: empty output,
            // runaway length, or output that abandoned the input words
            // (refusals, translations, hallucinated rambling).
            guard !out.isEmpty, out.count <= Int(Double(text.count) * 1.4) + 30 else {
                DebugTrace.append("polish rejected (length)", out)
                Log.info("polish rejected: length \(text.count) -> \(out.count)")
                return text
            }
            guard Self.sharesEnoughWords(input: text, output: out) else {
                DebugTrace.append("polish rejected (drifted from input)", out)
                Log.info("polish rejected: output drifted from input")
                return text
            }
            guard !Self.hasLoopedRepetition(output: out, input: text) else {
                DebugTrace.append("polish rejected (repetition loop)", out)
                Log.info("polish rejected: repetition loop")
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

    // The rewrite must stay anchored to the input: most input words should
    // survive into the output. Refusals ("Please tell me what to read"),
    // language switches, and reversed gibberish all fail this cheaply.
    static func sharesEnoughWords(input: String, output: String) -> Bool {
        let inputWords = Set(words(of: input))
        guard inputWords.count >= 3 else { return true }
        let outputWords = Set(words(of: output))
        let common = inputWords.intersection(outputWords).count
        return Double(common) / Double(inputWords.count) >= 0.5
    }

    private static func words(of text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }

    // Small models loop: seen live as the input sentence duplicated with a
    // garbage joint ("... voice quality. ieux TTS model, which would ...").
    // A four word sequence appearing twice in the output but not in the
    // input means the model repeated itself.
    static func hasLoopedRepetition(output: String, input: String) -> Bool {
        func repeatedFourgrams(_ text: String) -> Set<String> {
            let ws = words(of: text)
            guard ws.count >= 8 else { return [] }
            var seen = Set<String>()
            var repeated = Set<String>()
            for i in 0 ... (ws.count - 4) {
                let gram = ws[i ..< i + 4].joined(separator: " ")
                if !seen.insert(gram).inserted {
                    repeated.insert(gram)
                }
            }
            return repeated
        }
        let inputRepeats = repeatedFourgrams(input)
        return !repeatedFourgrams(output).subtracting(inputRepeats).isEmpty
    }

    // Small models leak chat template tokens into the text (seen in the
    // logs: "<end_of_turn><end_of_turn> numerically."). Spoken aloud they are
    // garbage, so strip every special token shape before use.
    static func sanitize(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(
            of: #"<\|?[a-zA-Z0-9_]+\|?>"#,
            with: " ",
            options: .regularExpression
        )
        s = s.replacingOccurrences(of: "```", with: " ")
        s = s.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
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
