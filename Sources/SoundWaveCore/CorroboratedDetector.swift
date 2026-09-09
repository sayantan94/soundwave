import Foundation

/// Both emitted tones must see a compatible reflection before motion is exposed.
/// An unrelated sound near just one pilot cannot select a direction.
public final class CorroboratedDetector {
    public let frequency: Double
    public let companionFrequency: Double
    private let primary: DopplerDetector
    private let companion: DopplerDetector
    private let binHz: Double

    public static func companion(for frequency: Double) -> Double {
        frequency >= 19500 ? frequency - 1000 : frequency + 1000
    }

    public init(sampleRate: Double, frequency: Double, sensitivity: Double = 0.5) {
        self.frequency = frequency
        companionFrequency = Self.companion(for: frequency)
        binHz = sampleRate / 4096
        // Keep each analysis region clear of the other pilot and its reflections.
        primary = DopplerDetector(sampleRate: sampleRate, frequency: frequency, bandwidth: 350)
        companion = DopplerDetector(sampleRate: sampleRate, frequency: companionFrequency, bandwidth: 350)
        primary.sensitivity = sensitivity
        companion.sensitivity = sensitivity
    }

    public func discardBufferedAudio() {
        primary.discardBufferedAudio()
        companion.discardBufferedAudio()
    }

    public func process(_ samples: [Float]) -> [Detection] {
        let first = primary.process(samples)
        let second = companion.process(samples)
        return zip(first, second).map { a, b in
            var result = a
            result.calibration = min(a.calibration, b.calibration)
            result.signalGood = a.signalGood && b.signalGood
            result.signalDB = min(a.signalDB, b.signalDB)
            result.signalToNoiseDB = min(a.signalToNoiseDB, b.signalToNoiseDB)
            result.activity = min(a.activity, b.activity)
            let companionShift = b.shiftHz * frequency / companionFrequency
            let tolerance = max(binHz * 2, max(abs(a.shiftHz), abs(companionShift)) * 0.35)
            let agrees = result.signalGood && a.motion * b.motion > 0
                && abs(a.shiftHz - companionShift) <= tolerance
            result.corroborated = agrees
            result.motion = agrees ? (a.motion > 0 ? 1 : -1) * min(abs(a.motion), abs(b.motion)) : 0
            result.confidence = agrees ? min(a.confidence, b.confidence) : 0
            result.shiftHz = agrees ? (a.shiftHz + companionShift) / 2 : 0
            return result
        }
    }
}
