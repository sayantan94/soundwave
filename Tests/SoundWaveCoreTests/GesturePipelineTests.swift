import XCTest
@testable import SoundWaveCore

final class GesturePipelineTests: XCTestCase {
    private func replay(onset: Double, shift: Double, returnStroke: Bool = false) -> [(Double, Int)] {
        let rate = 48000.0
        let detector = DopplerDetector(sampleRate: rate, frequency: 20000)
        var recognizer = GestureRecognizer()
        var events: [(Double, Int)] = []
        let total = Int((onset + 0.8) * rate)
        for start in stride(from: 0, to: total, by: 128) {
            let audio: [Float] = (start..<min(total, start + 128)).map { index in
                let time = Double(index) / rate
                var value = 0.15 * sin(2 * .pi * 20000 * time)
                if time >= onset && time < onset + 0.16 {
                    value += 0.035 * sin(2 * .pi * (20000 + shift) * time)
                }
                if returnStroke && time >= onset + 0.20 && time < onset + 0.44 {
                    value += 0.035 * sin(2 * .pi * (20000 - shift) * time)
                }
                return Float(value)
            }
            for frame in detector.process(audio) {
                let result = recognizer.update(motion: frame.motion, confidence: frame.confidence, activity: frame.activity,
                                               signalGood: frame.signalGood && frame.calibration >= 1, time: frame.sampleTime)
                if let direction = result.acceptedDirection { events.append((frame.sampleTime, direction)) }
            }
        }
        return events
    }

    func testShortStrokeIsAcceptedWithinOneHundredMillisecondsOfSyntheticEchoOnset() {
        var latencies: [Double] = []
        for shift in [-150.0, -55.0, 55.0, 180.0] {
            for onset in [3.7, 3.707] {
                let events = replay(onset: onset, shift: shift)
                XCTAssertEqual(events.count, 1)
                guard let event = events.first else { continue }
                XCTAssertEqual(event.1, shift > 0 ? 1 : -1)
                XCTAssertLessThanOrEqual(event.0 - onset, 0.1)
                latencies.append((event.0 - onset) * 1000)
            }
        }
        print("Synthetic echo onset → accepted gesture (ms): \(latencies.map { Int($0.rounded()) })")
    }

    func testPushThenReturnProducesExactlyOneActionThroughFullDSPPipeline() {
        for shift in [-180.0, -55.0, 55.0, 180.0] {
            let events = replay(onset: 3.7, shift: shift, returnStroke: true)
            XCTAssertEqual(events.map(\.1), [shift > 0 ? 1 : -1])
        }
    }
}
