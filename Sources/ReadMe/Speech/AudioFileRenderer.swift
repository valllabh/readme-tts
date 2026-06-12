import AVFoundation
import Foundation
import ReadMeCore

// Renders the speech pipeline into an audio file instead of the speakers.
// Two formats only: m4a (AAC, small, portable) and wav (lossless).
enum AudioFileRenderer {
    enum Format {
        case m4a
        case wav
    }

    static func render(text: String, to url: URL, format: Format) async throws -> Double {
        switch format {
        case .wav:
            return try await renderWAV(text: text, to: url)
        case .m4a:
            // AAC goes through a temp WAV plus afconvert: AVAudioFile's
            // direct AAC writing rejects this configuration, and afconvert
            // ships with macOS.
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
        let model = try await EngineManager.shared.model(for: Preferences.engine)
        let sampleRate = Double(model.sampleRate)

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
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        var totalFrames = 0
        let chunkCount = try await SpeechPipeline.run(
            text: text,
            model: model,
            options: SpeechPipeline.Options(
                polishFirstChunk: true,
                fastFirstChunk: false
            )
        ) { samples in
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

        guard chunkCount > 0, totalFrames > 0 else {
            throw NSError(domain: "ReadMe", code: 3, userInfo: [NSLocalizedDescriptionKey: "nothing readable in the input"])
        }
        return Double(totalFrames) / sampleRate
    }
}
