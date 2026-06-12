import ReadMeCore
import Foundation
import HuggingFace
import MLXAudioTTS

// Loads TTS models on demand and keeps them warm so repeated reads start fast.
actor EngineManager {
    static let shared = EngineManager()

    private var loaded: [EngineKind: SpeechGenerationModel] = [:]
    private var loadingTasks: [EngineKind: Task<SpeechGenerationModel, Error>] = [:]

    func model(for kind: EngineKind) async throws -> SpeechGenerationModel {
        if let model = loaded[kind] {
            return model
        }
        if let task = loadingTasks[kind] {
            return try await task.value
        }
        let task = Task<SpeechGenerationModel, Error> {
            try await Self.loadWithRecovery(kind)
        }
        loadingTasks[kind] = task
        defer { loadingTasks[kind] = nil }
        let model = try await task.value
        loaded[kind] = model
        return model
    }

    func isLoaded(_ kind: EngineKind) -> Bool {
        loaded[kind] != nil
    }

    private var primed: Set<EngineKind> = []

    // Preload the default engine at app start, then run a tiny throwaway
    // generation. MLX compiles Metal kernels lazily, so without priming the
    // first real read pays seconds of kernel compilation.
    func warmUp(_ kind: EngineKind) async {
        guard let model = try? await model(for: kind) else { return }
        guard !primed.contains(kind) else { return }
        primed.insert(kind)
        let start = Date()
        _ = try? await model.generate(
            text: "Hi.",
            voice: kind.defaultVoice,
            refAudio: nil,
            refText: nil,
            language: nil,
            generationParameters: nil
        )
        Log.info("engine primed in \(Int(Date().timeIntervalSince(start) * 1000)) ms")
    }

    // An interrupted download can leave a partial model directory that the
    // upstream cache check accepts (any nonzero safetensors file passes). If
    // loading fails, purge the cached snapshot and retry once with a fresh
    // download.
    private static func loadWithRecovery(_ kind: EngineKind) async throws -> SpeechGenerationModel {
        do {
            return try await TTS.loadModel(modelRepo: kind.modelRepo, modelType: kind.modelType)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Log.error("model load failed (\(error)), purging cache and retrying once")
            purgeModelCache(for: kind)
            return try await TTS.loadModel(modelRepo: kind.modelRepo, modelType: kind.modelType)
        }
    }

    private static func purgeModelCache(for kind: EngineKind) {
        let subdir = kind.modelRepo.replacingOccurrences(of: "/", with: "_")
        let dir = HubCache.default.cacheDirectory
            .appendingPathComponent("mlx-audio")
            .appendingPathComponent(subdir)
        try? FileManager.default.removeItem(at: dir)
    }
}
