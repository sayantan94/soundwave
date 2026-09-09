import XCTest
@testable import SoundWaveCore

final class DopplerDetectorTests: XCTestCase {
    private func samples(rate: Double = 48000, frequency: Double = 20000, duration: Double,
                         offset: Int = 0, shift: Double = 0, echo: Double = 0,
                         pilot: Double = 0.15, both: Bool = false) -> [Float] {
        (0..<Int(rate * duration)).map { i in
            let t = Double(i + offset) / rate
            var value = pilot * sin(2 * .pi * frequency * t)
            value += echo * sin(2 * .pi * (frequency + shift) * t)
            if both { value += echo * sin(2 * .pi * (frequency - shift) * t) }
            value += 0.0001 * sin(2 * .pi * 17431 * t)
            return Float(value)
        }
    }

    private func calibrated(rate: Double = 48000, frequency: Double = 20000) -> DopplerDetector {
        let detector = DopplerDetector(sampleRate: rate, frequency: frequency)
        let output = detector.process(samples(rate: rate, frequency: frequency, duration: 3.5))
        XCTAssertEqual(output.last?.calibration, 1)
        XCTAssertTrue(output.allSatisfy { $0.motion == 0 })
        return detector
    }

    func testStationaryToneDoesNotScrollAtBothSampleRates() {
        for rate in [44100.0, 48000.0] {
            let detector = calibrated(rate: rate)
            let output = detector.process(samples(rate: rate, duration: 1, offset: Int(rate * 3.5)))
            XCTAssertTrue(output.allSatisfy { $0.motion == 0 })
            XCTAssertTrue(output.last!.signalGood)
        }
    }

    func testTowardAndAwayEchoesAtBothSampleRates() {
        for rate in [44100.0, 48000.0] {
            for shift in [-180.0, 180.0] {
                let detector = calibrated(rate: rate)
                let output = detector.process(samples(rate: rate, duration: 0.6, offset: Int(rate * 3.5), shift: shift, echo: 0.035))
                let stable = output.suffix(8)
                XCTAssertTrue(stable.allSatisfy { $0.motion * shift > 0 }, "Failed direction \(shift) at \(rate)")
                XCTAssertEqual(stable.last!.shiftHz, shift, accuracy: 20)
            }
        }
    }

    func testNoCalibrationWithoutPilot() {
        let detector = DopplerDetector(sampleRate: 48000, frequency: 20000)
        let output = detector.process([Float](repeating: 0, count: 48000 * 4))
        XCTAssertEqual(output.last!.calibration, 0)
        XCTAssertFalse(output.last!.signalGood)
        XCTAssertTrue(output.allSatisfy { $0.motion == 0 })
    }

    func testModerateSpeedGesturesKeepTheirDirection() {
        for rate in [44100.0, 48000.0] {
            for shift in [-55.0, 55.0] {
                let detector = calibrated(rate: rate)
                let output = detector.process(samples(rate: rate, duration: 0.3, offset: Int(rate * 3.5), shift: shift, echo: 0.035))
                XCTAssertTrue(output.suffix(8).allSatisfy { $0.motion * shift > 0 }, "Missed moderate stroke \(shift) at \(rate)")
            }
        }
    }

    func testEqualEchoesHaveEqualConfidenceInBothDirections() {
        for rate in [44100.0, 48000.0] {
            for frequency in [19000.0, 20000.0, 20250.0] {
                var confidences: [Double] = []
                for shift in [-55.0, 55.0] {
                    let detector = calibrated(rate: rate, frequency: frequency)
                    let frames = detector.process(samples(rate: rate, frequency: frequency, duration: 0.3,
                        offset: Int(rate * 3.5), shift: shift, echo: 0.025)).suffix(8)
                    XCTAssertTrue(frames.allSatisfy { $0.motion * shift > 0 })
                    confidences.append(frames.map(\.confidence).reduce(0, +) / Double(frames.count))
                }
                XCTAssertEqual(confidences[0], confidences[1], accuracy: 0.02,
                    "Unequal direction confidence at \(frequency) Hz / \(rate)")
            }
        }
    }

    func testSignalLossStopsMotion() {
        let detector = calibrated()
        _ = detector.process(samples(duration: 0.5, offset: 168000, shift: 180, echo: 0.035))
        let output = detector.process([Float](repeating: 0, count: 24000))
        XCTAssertTrue(output.suffix(8).allSatisfy { !$0.signalGood && $0.motion == 0 })
    }

    func testSlowReturnAndAmbiguousMotionAreRejected() {
        let slow = calibrated().process(samples(duration: 0.6, offset: 168000, shift: 25, echo: 0.035))
        XCTAssertTrue(slow.suffix(8).allSatisfy { $0.motion == 0 })
        let both = calibrated().process(samples(duration: 0.6, offset: 168000, shift: 180, echo: 0.035, both: true))
        XCTAssertTrue(both.suffix(8).allSatisfy { $0.motion == 0 })
    }

    func testVolumeChangeDoesNotCreateSustainedMotion() {
        let detector = calibrated()
        let output = detector.process(samples(duration: 0.7, offset: 168000, pilot: 0.4))
        XCTAssertTrue(output.suffix(12).allSatisfy { $0.motion == 0 })
    }

    func testIrregularBufferSizesMatchContiguousInput() {
        let signal = samples(duration: 3.8, shift: 180, echo: 0)
        let full = DopplerDetector(sampleRate: 48000, frequency: 20000).process(signal)
        let chunked = DopplerDetector(sampleRate: 48000, frequency: 20000)
        var result: [Detection] = []
        var start = 0
        while start < signal.count {
            let end = min(signal.count, start + 777)
            result += chunked.process(Array(signal[start..<end]))
            start = end
        }
        XCTAssertEqual(result.count, full.count)
        XCTAssertEqual(result.last!.signalDB, full.last!.signalDB, accuracy: 0.001)
        XCTAssertEqual(result.last!.calibration, full.last!.calibration)
    }
}
