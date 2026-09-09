import XCTest
@testable import SoundWaveCore

final class GestureRecognizerTests: XCTestCase {
    private func feed(_ recognizer: inout GestureRecognizer, time: inout Double, duration: Double,
                      motion: Double = 0, confidence: Double = 1, activity: Double? = nil,
                      good: Bool = true, step: Double = 0.01) -> [Int] {
        var actions: [Int] = []
        for _ in 0..<Int((duration / step).rounded()) {
            time += step
            let result = recognizer.update(motion: motion, confidence: confidence, activity: activity ?? (motion == 0 ? 0 : 1), signalGood: good, time: time)
            if let direction = result.acceptedDirection { actions.append(direction) }
        }
        return actions
    }

    func testResponsiveStrokeAcceptsWithinTwentyMillisecondsAfterEvidenceStarts() {
        var recognizer = GestureRecognizer(); var time = 0.0
        _ = feed(&recognizer, time: &time, duration: 0.2)
        XCTAssertEqual(feed(&recognizer, time: &time, duration: 0.02, motion: 0.7), [1])
    }
    func testSingleSpikeDoesNotFire() {
        var recognizer = GestureRecognizer(); var time = 0.0
        _ = feed(&recognizer, time: &time, duration: 0.2)
        XCTAssertTrue(feed(&recognizer, time: &time, duration: 0.01, motion: 1).isEmpty)
        XCTAssertTrue(feed(&recognizer, time: &time, duration: 0.4).isEmpty)
    }
    func testSustainedStrokeFiresExactlyOnce() {
        var recognizer = GestureRecognizer(); var time = 0.0
        _ = feed(&recognizer, time: &time, duration: 0.2)
        XCTAssertEqual(feed(&recognizer, time: &time, duration: 4, motion: 0.7), [1])
    }
    func testReturnStrokeIsSwallowedAndNextDeliberateStrokeWorks() {
        var recognizer = GestureRecognizer(); var time = 0.0
        _ = feed(&recognizer, time: &time, duration: 0.2)
        XCTAssertEqual(feed(&recognizer, time: &time, duration: 0.2, motion: 0.7), [1])
        _ = feed(&recognizer, time: &time, duration: 0.06)
        XCTAssertTrue(feed(&recognizer, time: &time, duration: 0.7, motion: -0.5).isEmpty)
        _ = feed(&recognizer, time: &time, duration: 0.25)
        XCTAssertEqual(feed(&recognizer, time: &time, duration: 0.2, motion: -0.7), [-1])
    }
    func testSignalFlickerCannotResetCooldownOrCreateDuplicates() {
        var recognizer = GestureRecognizer(); var time = 0.0
        _ = feed(&recognizer, time: &time, duration: 0.2)
        XCTAssertEqual(feed(&recognizer, time: &time, duration: 0.1, motion: 0.7), [1])
        for _ in 0..<20 {
            XCTAssertTrue(feed(&recognizer, time: &time, duration: 0.02, good: false).isEmpty)
            XCTAssertTrue(feed(&recognizer, time: &time, duration: 0.04, motion: 0.7).isEmpty)
        }
    }
    func testAmbiguousMovementCannotRearmRecognizer() {
        var recognizer = GestureRecognizer(); var time = 0.0
        _ = feed(&recognizer, time: &time, duration: 0.2)
        _ = feed(&recognizer, time: &time, duration: 0.1, motion: 0.7)
        _ = feed(&recognizer, time: &time, duration: 1, confidence: 0, activity: 1)
        XCTAssertTrue(feed(&recognizer, time: &time, duration: 0.2, motion: -0.7).isEmpty)
    }
    func testAlternatingDirectionAndLowConfidenceAreRejected() {
        var recognizer = GestureRecognizer(); var time = 0.0
        _ = feed(&recognizer, time: &time, duration: 0.2)
        for i in 0..<100 {
            XCTAssertTrue(feed(&recognizer, time: &time, duration: 0.01, motion: i.isMultiple(of: 2) ? 0.6 : -0.6).isEmpty)
        }
        XCTAssertTrue(feed(&recognizer, time: &time, duration: 0.5, motion: 0.8, confidence: 0.3).isEmpty)
    }
    func testDelayedProcessingCannotCompleteAnOldGesture() {
        var recognizer = GestureRecognizer(); var time = 0.0
        _ = feed(&recognizer, time: &time, duration: 0.2)
        _ = feed(&recognizer, time: &time, duration: 0.01, motion: 0.8)
        time += 2
        XCTAssertTrue(feed(&recognizer, time: &time, duration: 0.3, motion: 0.8).isEmpty)
    }
}
