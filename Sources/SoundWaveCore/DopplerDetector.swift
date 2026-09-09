import Accelerate
import Foundation

public struct Detection {
    public var calibration: Double
    public var signalDB: Double
    public var signalGood: Bool
    /// Positive is toward the speaker/microphone; negative is away.
    public var motion: Double
    public var shiftHz: Double
    public var spectrum: [Double]
    public var confidence: Double = 0
    public var activity: Double = 0
    public var sampleTime: Double = 0
    public var signalToNoiseDB: Double = 0
}

/// A streaming, overlapping FFT detector. All access belongs on one analysis queue.
public final class DopplerDetector {
    public let sampleRate: Double
    public let frequency: Double
    public var sensitivity: Double = 0.5
    private let size = 4096
    private let hop = 512
    private let setup: FFTSetup
    private var window: [Float]
    private var real: [Float]
    private var imaginary: [Float]
    private var pending: [Float] = []
    private var baseline: [Double]
    private var frames = 0
    private var candidate = 0
    private var consecutive = 0
    private var settlingFrames: Int
    private let calibrationFrames: Int
    private var processedSamples = 0

    public init(sampleRate: Double, frequency: Double) {
        precondition(sampleRate >= 44100 && frequency > 1000 && frequency + 1000 < sampleRate / 2)
        self.sampleRate = sampleRate
        self.frequency = frequency
        self.setup = vDSP_create_fftsetup(12, FFTRadix(kFFTRadix2))!
        window = [Float](repeating: 0, count: size)
        real = window
        imaginary = window
        baseline = [Double](repeating: 0, count: size / 2)
        calibrationFrames = Int(2.5 * sampleRate / Double(hop))
        settlingFrames = Int(0.3 * sampleRate / Double(hop))
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        pending.reserveCapacity(size * 3)
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// Keep room calibration, but don't bridge a discontinuity in captured audio.
    public func discardBufferedAudio() {
        pending.removeAll(keepingCapacity: true)
        processedSamples = 0
        candidate = 0
        consecutive = 0
    }

    public func process(_ samples: [Float]) -> [Detection] {
        pending.append(contentsOf: samples)
        var output: [Detection] = []
        var offset = 0
        while pending.count - offset >= size {
            for i in 0..<size {
                real[i] = pending[offset + i] * window[i]
                imaginary[i] = 0
            }
            real.withUnsafeMutableBufferPointer { r in
                imaginary.withUnsafeMutableBufferPointer { im in
                    var complex = DSPSplitComplex(realp: r.baseAddress!, imagp: im.baseAddress!)
                    vDSP_fft_zip(setup, &complex, 1, 12, FFTDirection(FFT_FORWARD))
                }
            }
            var detection = analyze()
            detection.sampleTime = Double(processedSamples + size) / sampleRate
            output.append(detection)
            offset += hop
            processedSamples += hop
        }
        if offset > 0 { pending.removeFirst(offset) }
        return output
    }

    private func analyze() -> Detection {
        let binHz = sampleRate / Double(size)
        let center = Int((frequency / binHz).rounded())
        let radius = Int(650 / binHz)
        let range = (center - radius)...(center + radius)
        let normalization = pow(Double(size) / 4, 2)
        var power = [Double](repeating: 0, count: size / 2)
        for i in range {
            power[i] = (Double(real[i]) * Double(real[i]) + Double(imaginary[i]) * Double(imaginary[i])) / normalization
        }
        let pilot = ((center - 2)...(center + 2)).map { power[$0] }.max() ?? 0
        let noiseBins = range.filter { abs($0 - center) > radius * 3 / 4 }.map { power[$0] }.sorted()
        let noise = max(1e-12, noiseBins[noiseBins.count / 2])
        let signalDB = 10 * log10(max(pilot, 1e-12))
        let signalGood = signalDB > -75 && pilot > noise * 80
        let spectrum = range.map { max(0, min(1, (10 * log10(max(power[$0], 1e-12)) + 100) / 90)) }

        if settlingFrames > 0 {
            settlingFrames -= 1
            return Detection(calibration: 0, signalDB: signalDB, signalGood: signalGood, motion: 0, shiftHz: 0, spectrum: spectrum)
        }
        if frames < calibrationFrames {
            // Average relative power so a volume change doesn't look like a gesture.
            if signalGood {
                frames += 1
                for i in range { baseline[i] += (power[i] / max(pilot, 1e-12) - baseline[i]) / Double(frames) }
            }
            return Detection(calibration: Double(frames) / Double(calibrationFrames), signalDB: signalDB, signalGood: signalGood, motion: 0, shiftHz: 0, spectrum: spectrum)
        }

        var low = 0.0, high = 0.0, lowWeighted = 0.0, highWeighted = 0.0
        // A dead band rejects the direct tone and slow return movements.
        let deadBand = max(4, Int(75 / binHz))
        let threshold = 0.025 * pow(0.08, min(1, max(0, sensitivity)))
        for i in range where abs(i - center) >= deadBand {
            let relative = power[i] / max(pilot, 1e-12)
            let floor = max(baseline[i] * 3, noise / max(pilot, 1e-12) * 6)
            let excess = max(0, relative - floor - threshold)
            if i < center {
                low += excess
                lowWeighted += excess * Double(center - i) * binHz
            } else {
                high += excess
                highWeighted += excess * Double(i - center) * binHz
            }
        }
        var direction = 0
        if signalGood {
            if high > threshold * 2 && high > low * 2.2 { direction = 1 }
            if low > threshold * 2 && low > high * 2.2 { direction = -1 }
        }
        if direction != 0 && direction == candidate { consecutive += 1 }
        else { candidate = direction; consecutive = direction == 0 ? 0 : 1 }
        var shift = 0.0
        var motion = 0.0
        if consecutive >= 2 {
            shift = direction > 0 ? highWeighted / high : -lowWeighted / low
            motion = Double(direction) * min(1, max(0.2, abs(shift) / 300))
        }
        if direction == 0 && signalGood {
            for i in range {
                let relative = power[i] / max(pilot, 1e-12)
                baseline[i] += 0.002 * (relative - baseline[i])
            }
        }
        var detection = Detection(calibration: 1, signalDB: signalDB, signalGood: signalGood, motion: motion, shiftHz: shift, spectrum: spectrum)
        let strength = max(low, high)
        detection.confidence = abs(high - low) / max(1e-12, high + low) * min(1, strength / (threshold * 4))
        detection.activity = min(1, (low + high) / (threshold * 4))
        detection.signalToNoiseDB = 10 * log10(max(pilot, 1e-12) / noise)
        return detection
    }
}
