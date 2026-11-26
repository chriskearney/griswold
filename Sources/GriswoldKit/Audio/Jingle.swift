import AVFoundation
import Foundation

/// Tiny synthesiser for the optional sound effects. Nothing is loaded from disk:
/// each cue is computed into a buffer, played, and the audio engine shut down
/// again so the app is not holding the sound hardware awake.
final class Jingle {
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var stopWork: DispatchWorkItem?
    private static let sampleRate: Double = 44_100

    private let synthesis = DispatchQueue(label: "net.chonkbase.griswold.audio", qos: .utility)

    /// Synthesises off the main thread (a long sleigh pass is millions of sine
    /// evaluations), then plays on it.
    func play(_ cue: SoundCue, volume: Float) {
        guard volume > 0.01 else { return }
        synthesis.async { [weak self] in
            let samples: [SIMD2<Float>]
            switch cue {
            case .sleighBells(let duration): samples = Jingle.sleighBells(duration: min(duration, 16))
            case .chime: samples = Jingle.chime()
            case .powerUp: samples = Jingle.powerUp()
            case .whoosh: samples = Jingle.whoosh()
            }
            DispatchQueue.main.async { self?.start(samples, volume: volume) }
        }
    }

    private func start(_ samples: [SIMD2<Float>], volume: Float) {
        guard !samples.isEmpty,
              let format = AVAudioFormat(standardFormatWithSampleRate: Jingle.sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channels = buffer.floatChannelData
        else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (index, sample) in samples.enumerated() {
            channels[0][index] = sample.x * volume
            channels[1][index] = sample.y * volume
        }

        if engine == nil {
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            self.engine = engine
            self.player = player
        }
        guard let engine, let player else { return }
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            return
        }
        player.scheduleBuffer(buffer, completionHandler: nil)
        player.play()

        stopWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.player?.stop()
            self?.engine?.stop()
        }
        stopWork = work
        let length = Double(samples.count) / Jingle.sampleRate
        DispatchQueue.main.asyncAfter(deadline: .now() + length + 0.5, execute: work)
    }

    // MARK: Synthesis

    /// A struck bell: a handful of inharmonic partials that die away quickly.
    private static func addBell(into out: inout [SIMD2<Float>], at start: Double, base: Double,
                                gain: Float, decay: Double, pan: Float, rng: inout FastRNG) {
        let ratios: [Double] = [1.0, 1.48, 2.09, 2.63, 3.41, 4.37]
        let weights: [Float] = [1.0, 0.7, 0.55, 0.4, 0.28, 0.18]
        let length = Int(sampleRate * min(5 / decay, 3))
        let first = Int(start * sampleRate)
        let left = gain * sqrtf(0.5 * (1 - pan))
        let right = gain * sqrtf(0.5 * (1 + pan))
        let detune = 1 + Double(rng.signed()) * 0.012
        for n in 0..<length {
            let index = first + n
            guard index >= 0, index < out.count else { break }
            let t = Double(n) / sampleRate
            var value: Float = 0
            for (k, ratio) in ratios.enumerated() {
                value += weights[k] * Float(sin(2 * .pi * base * ratio * detune * t) * exp(-t * decay * (1 + Double(k) * 0.35)))
            }
            // A little noise at the strike gives the metallic "ching".
            if n < 600 { value += rng.signed() * 0.5 * Float(1 - Double(n) / 600) }
            out[index] += SIMD2(value * left, value * right)
        }
    }

    static func sleighBells(duration: Double) -> [SIMD2<Float>] {
        var rng = FastRNG(seed: 0x5E11)
        var out = [SIMD2<Float>](repeating: .zero, count: Int((duration + 0.6) * sampleRate))
        let step = 0.142
        var time = 0.0
        var beat = 0
        while time < duration {
            let u = time / duration
            // Fades in, passes, fades away, sweeping across the speakers.
            let presence = Float(pow(sin(.pi * u), 0.9))
            let pan = Float(u * 2 - 1) * 0.75
            let accent: Float = beat % 4 == 0 ? 1 : (beat % 2 == 0 ? 0.72 : 0.5)
            for _ in 0..<3 {
                addBell(into: &out, at: time + Double(rng.unit()) * 0.018,
                        base: Double(rng.range(2300, 3300)),
                        gain: 0.055 * accent * presence, decay: 26, pan: pan, rng: &rng)
            }
            time += step
            beat += 1
        }
        return limit(out)
    }

    static func chime() -> [SIMD2<Float>] {
        var rng = FastRNG(seed: 0xC41)
        var out = [SIMD2<Float>](repeating: .zero, count: Int(2.4 * sampleRate))
        addBell(into: &out, at: 0, base: 1568, gain: 0.10, decay: 3.2, pan: -0.2, rng: &rng)
        addBell(into: &out, at: 0.09, base: 2093, gain: 0.07, decay: 3.6, pan: 0.25, rng: &rng)
        return limit(out)
    }

    /// A breaker thunk, then a warm chord swelling up.
    static func powerUp() -> [SIMD2<Float>] {
        var rng = FastRNG(seed: 0xB0B)
        let length = Int(3.2 * sampleRate)
        var out = [SIMD2<Float>](repeating: .zero, count: length)
        let chord: [Double] = [130.81, 196.0, 261.63, 329.63, 392.0, 523.25]
        for n in 0..<length {
            let t = Double(n) / sampleRate
            var value: Float = 0
            let thunk = exp(-t * 30)
            value += Float(sin(2 * .pi * 62 * t) * thunk) * 0.5
            if n < 900 { value += rng.signed() * 0.35 * Float(1 - Double(n) / 900) }
            let swell = Float(min(t / 0.5, 1) * exp(-max(t - 0.9, 0) * 1.5))
            for (k, frequency) in chord.enumerated() {
                value += Float(sin(2 * .pi * frequency * t + Double(k))) * 0.045 * swell
            }
            out[n] = SIMD2(value, value) * 0.5
        }
        return limit(out)
    }

    /// Three fast passes: filtered noise that swells, sweeps across, and is gone.
    static func whoosh() -> [SIMD2<Float>] {
        var rng = FastRNG(seed: 0x51ED)
        let length = Int(5.6 * sampleRate)
        var out = [SIMD2<Float>](repeating: .zero, count: length)
        var low: Float = 0
        var band: Float = 0
        for n in 0..<length {
            let t = Double(n) / sampleRate
            var gain: Float = 0
            var pan: Float = 0
            var cutoff: Float = 0.05
            for pass in 0..<3 {
                let u = (t - Double(pass) * 1.75) / 1.3
                guard u > 0, u < 1 else { continue }
                let swell = Float(pow(sin(.pi * u), 2.4))
                gain = swell * 0.5
                // Each pass comes from the opposite side.
                pan = Float(u * 2 - 1) * (pass % 2 == 0 ? 0.85 : -0.85)
                cutoff = 0.04 + 0.22 * swell
            }
            // A state-variable filter keeps the hiss in a moving band.
            let noise = rng.signed()
            low += cutoff * band
            let high = noise - low - 0.6 * band
            band += cutoff * high
            let value = band * gain
            out[n] = SIMD2(value * sqrtf(0.5 * (1 - pan)), value * sqrtf(0.5 * (1 + pan)))
        }
        return limit(out)
    }

    private static func limit(_ samples: [SIMD2<Float>]) -> [SIMD2<Float>] {
        samples.map { SIMD2(tanhf($0.x * 1.4) / 1.4, tanhf($0.y * 1.4) / 1.4) }
    }
}
