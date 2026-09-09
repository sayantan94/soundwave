import XCTest
@testable import SoundWaveCore

final class CorroboratedDetectorTests: XCTestCase {
    private func replay(primaryShift: Double?, companionShift: Double?, frequency: Double = 20000,
                        fadePilot: Bool = false) -> [(Double, Int)] {
        let rate = 48000.0
        let companion = CorroboratedDetector.companion(for: frequency)
        let detector = CorroboratedDetector(sampleRate: rate, frequency: frequency)
        var recognizer = GestureRecognizer()
        var events: [(Double, Int)] = []
        for start in stride(from: 0, to: Int(rate * 4.4), by: 512) {
            let samples = (start..<(start + 512)).map { index -> Float in
                let time = Double(index) / rate
                let active = time >= 3.7 && time < 4.05
                let amplitude = fadePilot && active ? 0.03 : 0.15
                var value = amplitude * (sin(2 * .pi * frequency * time) + sin(2 * .pi * companion * time))
                if active || fadePilot {
                    if let primaryShift { value += 0.035 * sin(2 * .pi * (frequency + primaryShift) * time) }
                    if let companionShift { value += 0.035 * sin(2 * .pi * (companion + companionShift) * time) }
                }
                return Float(value)
            }
            for frame in detector.process(samples) {
                let result = recognizer.update(motion: frame.motion, confidence: frame.confidence,
                    activity: frame.activity, signalGood: frame.signalGood && frame.calibration >= 1, time: frame.sampleTime)
                if let direction = result.acceptedDirection { events.append((frame.sampleTime, direction)) }
            }
        }
        return events
    }

    func testBothDirectionsStillRespondQuicklyWhenTonesAgree() {
        for frequency in [19000.0, 20000.0] {
            for shift in [-150.0, 150.0] {
                let scaled = shift * CorroboratedDetector.companion(for: frequency) / frequency
                let events = replay(primaryShift: shift, companionShift: scaled, frequency: frequency)
                XCTAssertEqual(events.map(\.1), [shift > 0 ? 1 : -1])
                if let event = events.first { XCTAssertLessThan(event.0 - 3.7, 0.13) }
            }
        }
    }

    func testNewInterferenceBesideEitherSingleToneCannotSwitchDesktops() {
        for shift in [-150.0, 150.0] {
            XCTAssertTrue(replay(primaryShift: shift, companionShift: nil).isEmpty)
            XCTAssertTrue(replay(primaryShift: nil, companionShift: shift).isEmpty)
        }
    }

    func testOppositeDirectionsAndIncompatibleSpeedsAreRejected() {
        XCTAssertTrue(replay(primaryShift: 150, companionShift: -150).isEmpty)
        XCTAssertTrue(replay(primaryShift: 80, companionShift: 250).isEmpty)
    }

    func testStationaryInterferenceStaysRejectedWhenBothPilotsFade() {
        XCTAssertTrue(replay(primaryShift: 150, companionShift: 142.5, fadePilot: true).isEmpty)
    }
}
