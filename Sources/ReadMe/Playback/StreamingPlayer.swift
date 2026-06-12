import AVFoundation
import Foundation

// Plays a growing stream of mono float samples with pause, stop, and seek.
// All generated audio is kept in a master buffer so seeking backward always
// works and seeking forward works up to whatever has been generated so far.
final class StreamingPlayer {
    enum State {
        case playing
        case paused
        case stopped
        case finished
    }

    // Called on the main queue whenever playback state changes.
    var onStateChange: ((State) -> Void)?

    private let audioEngine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let format: AVAudioFormat
    private let sampleRate: Int
    private let queue = DispatchQueue(label: "app.readme.player")

    private var samples: [Float] = []
    private var cursor = 0          // next sample index to schedule
    private var played = 0          // samples confirmed played back
    private var inFlight = 0        // scheduled buffers not yet played
    private var epoch = 0           // invalidates stale completion callbacks
    private var generationDone = false
    private var state: State = .stopped

    private let sliceLength: Int    // samples per scheduled buffer
    private let maxInFlight = 4

    init(sampleRate: Int, rate: Float = 1.0) throws {
        self.sampleRate = sampleRate
        self.sliceLength = max(1, sampleRate / 4)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(domain: "ReadMe", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bad audio format"])
        }
        self.format = format
        // Time pitch unit changes tempo without chipmunking the voice.
        timePitch.rate = Self.clampedRate(rate)
        audioEngine.attach(node)
        audioEngine.attach(timePitch)
        audioEngine.connect(node, to: timePitch, format: format)
        audioEngine.connect(timePitch, to: audioEngine.mainMixerNode, format: format)
        try audioEngine.start()
    }

    func setRate(_ rate: Float) {
        queue.async {
            self.timePitch.rate = Self.clampedRate(rate)
        }
    }

    private static func clampedRate(_ rate: Float) -> Float {
        min(max(rate, 0.5), 3.0)
    }

    // MARK: - Feeding

    func append(_ newSamples: [Float]) {
        guard !newSamples.isEmpty else { return }
        queue.async {
            self.samples.append(contentsOf: newSamples)
            if self.state == .stopped {
                self.state = .playing
                self.node.play()
                self.notify()
            }
            self.pump()
        }
    }

    func finishAppending() {
        queue.async {
            self.generationDone = true
            self.checkFinished()
        }
    }

    // MARK: - Transport

    func pause() {
        queue.async {
            guard self.state == .playing else { return }
            self.node.pause()
            self.state = .paused
            self.notify()
        }
    }

    func resume() {
        queue.async {
            guard self.state == .paused else { return }
            self.node.play()
            self.state = .playing
            self.notify()
        }
    }

    func togglePause() {
        queue.async {
            switch self.state {
            case .playing:
                self.node.pause()
                self.state = .paused
                self.notify()
            case .paused:
                self.node.play()
                self.state = .playing
                self.notify()
            default:
                break
            }
        }
    }

    func stop() {
        queue.async {
            self.epoch += 1
            self.inFlight = 0
            self.node.stop()
            self.audioEngine.stop()
            self.state = .stopped
            self.notify()
        }
    }

    func seek(bySeconds delta: Double) {
        queue.async {
            let offset = Int(delta * Double(self.sampleRate))
            self.seekLocked(to: self.played + offset)
        }
    }

    func seek(toSample target: Int) {
        queue.async {
            self.seekLocked(to: target)
        }
    }

    private func seekLocked(to rawTarget: Int) {
        Log.info("player: seek to \(rawTarget) from \(played) of \(samples.count)")
        guard state == .playing || state == .paused else { return }
        let target = min(max(rawTarget, 0), samples.count)
        epoch += 1
        inFlight = 0
        let wasPlaying = state == .playing
        node.stop()
        played = target
        cursor = target
        if wasPlaying {
            node.play()
        }
        pump()
        // A seek that lands at the end of generated audio schedules
        // nothing, so no completion callback will ever fire again.
        checkFinished()
    }

    var currentTime: Double {
        queue.sync { Double(played) / Double(sampleRate) }
    }

    var currentSample: Int {
        queue.sync { played }
    }

    var bufferedTime: Double {
        queue.sync { Double(samples.count) / Double(sampleRate) }
    }

    // MARK: - Internals

    // Schedules pending samples onto the player node, keeping a small number
    // of slices in flight so seek stays responsive.
    private func pump() {
        guard state == .playing || state == .paused else { return }
        let currentEpoch = epoch
        while cursor < samples.count && inFlight < maxInFlight {
            let end = min(cursor + sliceLength, samples.count)
            let count = end - cursor
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(count)
            ), let channel = buffer.floatChannelData?[0] else { return }
            buffer.frameLength = AVAudioFrameCount(count)
            samples.withUnsafeBufferPointer { ptr in
                channel.update(from: ptr.baseAddress! + cursor, count: count)
            }
            cursor = end
            inFlight += 1
            node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                guard let self else { return }
                self.queue.async {
                    guard self.epoch == currentEpoch else { return }
                    self.played += count
                    self.inFlight -= 1
                    self.pump()
                    self.checkFinished()
                }
            }
        }
    }

    private func checkFinished() {
        // Finishing must work from any live state: .playing and .paused for
        // normal playback, and .stopped for the case where generation
        // produced no audio at all and the player never started.
        guard generationDone, state != .finished else { return }
        if cursor >= samples.count && inFlight == 0 {
            node.stop()
            audioEngine.stop()
            state = .finished
            notify()
        }
    }

    private func notify() {
        let s = state
        Log.info("player: state=\(s) played=\(played) buffered=\(samples.count)")
        DispatchQueue.main.async { [weak self] in
            self?.onStateChange?(s)
        }
    }
}
