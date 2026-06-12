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

    private static let instructions = """
    You rewrite text so it can be read aloud naturally by a text to speech \
    voice. Keep every piece of information and the original wording wherever \
    it already sounds natural. Spell out anything a voice would stumble on: \
    symbols, file names, version numbers, acronyms that are spoken letter by \
    letter, units, and code fragments. Never summarize, never shorten, never \
    add commentary or introductions. Respond with the rewritten text only.
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
        guard !text.isEmpty else { return text }
        // Use the model only if it is already in memory; never delay speech.
        guard let container else { return text }
        do {
            let session = ChatSession(
                container,
                instructions: Self.instructions,
                generateParameters: GenerateParameters(maxTokens: 700, temperature: 0.0)
            )
            let raw = try await session.respond(to: text)
            let out = Self.sanitize(raw)
            // Guard against the model going off script: empty output or
            // runaway length falls back to the input.
            guard !out.isEmpty, out.count < max(text.count * 3, 200) else { return text }
            // Log sizes only. The text itself is whatever the user selected
            // and must never be persisted to disk.
            Log.info("polish: \(text.count) -> \(out.count) chars, changed=\(out != text)")
            return out
        } catch {
            Log.error("polish failed, using plain text: \(error)")
            return text
        }
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
