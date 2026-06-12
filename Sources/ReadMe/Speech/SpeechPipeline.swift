import Foundation
import MLXAudioTTS
import ReadMeCore

// The one place the full read pipeline lives: segment, normalize, chunk,
// optional polish (prefetched between generations so it never competes with
// TTS for the GPU), generate, and inject structural silence. Consumers
// differ only in where samples go: the streaming player or an audio file.
enum SpeechPipeline {
    struct Options {
        // Polish chunk one too. The live player skips it for instant start;
        // file rendering has no latency constraint.
        var polishFirstChunk: Bool
        // Fine streaming interval on chunk one for the earliest first audio.
        var fastFirstChunk: Bool
    }

    // Runs the pipeline, emitting mono float samples at model.sampleRate.
    // Returns the number of chunks spoken; zero means nothing readable.
    static func run(
        text: String,
        model: SpeechGenerationModel,
        options: Options,
        onChunkStart: ((_ sampleOffset: Int) -> Void)? = nil,
        emit: ([Float]) throws -> Void
    ) async throws -> Int {
        var emittedTotal = 0
        let polish = Preferences.aiScriptEnabled
        let voice = Preferences.voice.isEmpty ? Preferences.engine.defaultVoice : Preferences.voice
        let sampleRate = Double(model.sampleRate)

        let segments = TextSegmenter.segments(of: text)
        Log.info("pipeline: \(segments.count) segments")

        var globalIndex = 0
        var nextPolish: Task<String, Never>?

        for (segmentIndex, segment) in segments.enumerated() {
            try Task.checkCancellation()
            var pieces = SentenceChunker.chunks(for: TextNormalizer.normalize(segment))
            guard !pieces.isEmpty else { continue }
            // The chunker zeroes the trailing pause; a segment boundary mid
            // selection is still a paragraph break.
            if segmentIndex + 1 < segments.count, let last = pieces.last {
                pieces[pieces.count - 1] = SpeechChunk(
                    text: last.text,
                    pauseAfter: SentenceChunker.paragraphPause
                )
            }
            Log.info("pipeline: segment \(segmentIndex + 1)/\(segments.count), \(pieces.count) chunks")

            for (pieceIndex, piece) in pieces.enumerated() {
                try Task.checkCancellation()
                let index = globalIndex
                globalIndex += 1

                let spokenText: String
                if let pending = nextPolish {
                    spokenText = await pending.value
                    nextPolish = nil
                } else if polish, options.polishFirstChunk || index > 0 {
                    spokenText = await ScriptPreparer.shared.prepare(piece.text)
                } else {
                    spokenText = piece.text
                }

                DebugTrace.append("TTS chunk \(index + 1), pause \(piece.pauseAfter)s", spokenText)
                onChunkStart?(emittedTotal)

                let stream = model.generateSamplesStream(
                    text: spokenText,
                    voice: voice,
                    refAudio: nil,
                    refText: nil,
                    language: nil,
                    generationParameters: nil,
                    streamingInterval: options.fastFirstChunk && index == 0 ? 0.2 : 1.0
                )
                // Duration watchdog: speech runs two to three words per
                // second, so audio far past that is the model rambling in
                // hallucinated phonemes (its known failure on digit and
                // symbol heavy input). Truncating the chunk cuts the damage
                // and the next chunk re-anchors generation from scratch.
                let words = spokenText.split { $0 == " " }.count
                let allowedSeconds = 2.0 + Double(words) * 0.5
                var emittedSamples = 0
                for try await samples in stream {
                    try Task.checkCancellation()
                    try emit(samples)
                    emittedSamples += samples.count
                    emittedTotal += samples.count
                    if Double(emittedSamples) > allowedSeconds * sampleRate {
                        Log.error("pipeline: chunk \(index + 1) hit \(Int(Double(emittedSamples) / sampleRate))s of audio for \(words) words (allowed \(Int(allowedSeconds))s), truncating likely hallucination")
                        break
                    }
                }

                // Prefetch the polish for the next chunk in this segment now
                // that the GPU is free; it runs while audio plays or, for
                // file rendering, while nothing else needs the GPU.
                if polish, pieceIndex + 1 < pieces.count {
                    let upcoming = pieces[pieceIndex + 1].text
                    nextPolish = Task {
                        await ScriptPreparer.shared.prepare(upcoming)
                    }
                }
                // The model never sees line or paragraph breaks, so
                // structural pauses are injected as real silence.
                if piece.pauseAfter > 0 {
                    let silence = Int(piece.pauseAfter * sampleRate)
                    try emit([Float](repeating: 0, count: silence))
                    emittedTotal += silence
                }
            }
        }
        return globalIndex
    }
}
