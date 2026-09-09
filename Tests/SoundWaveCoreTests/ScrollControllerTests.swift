import XCTest
@testable import SoundWaveCore

final class ScrollControllerTests: XCTestCase {
    func testDirectionReverseAndPause() {
        var scroll = ScrollController()
        XCTAssertEqual(scroll.update(motion: 1, now: 0, enabled: true, speed: 600, reversed: false), 0)
        XCTAssertLessThan(scroll.update(motion: 1, now: 0.02, enabled: true, speed: 600, reversed: false), 0)
        XCTAssertGreaterThan(scroll.update(motion: 1, now: 0.04, enabled: true, speed: 600, reversed: true), 0)
        XCTAssertEqual(scroll.update(motion: 1, now: 0.06, enabled: false, speed: 600, reversed: false), 0)
        XCTAssertEqual(scroll.update(motion: 1, now: 10, enabled: true, speed: 600, reversed: false), 0)
    }

    func testNoMotionMeansNoMomentum() {
        var scroll = ScrollController()
        _ = scroll.update(motion: 1, now: 0, enabled: true, speed: 600, reversed: false)
        _ = scroll.update(motion: 1, now: 0.02, enabled: true, speed: 600, reversed: false)
        XCTAssertEqual(scroll.update(motion: 0, now: 0.04, enabled: true, speed: 600, reversed: false), 0)
    }

    func testQuickReturnStrokeIsSuppressed() {
        var scroll = ScrollController()
        _ = scroll.update(motion: 1, now: 0, enabled: true, speed: 600, reversed: false)
        _ = scroll.update(motion: 1, now: 0.02, enabled: true, speed: 600, reversed: false)
        XCTAssertEqual(scroll.update(motion: -1, now: 0.04, enabled: true, speed: 600, reversed: false), 0)
        XCTAssertEqual(scroll.update(motion: -1, now: 0.1, enabled: true, speed: 600, reversed: false), 0)
        XCTAssertGreaterThan(scroll.update(motion: -1, now: 0.32, enabled: true, speed: 600, reversed: false), 0)
    }

    func testDelayedFrameIsBounded() {
        var scroll = ScrollController()
        _ = scroll.update(motion: 1, now: 0, enabled: true, speed: 600, reversed: false)
        XCTAssertEqual(scroll.update(motion: 1, now: 100, enabled: true, speed: 600, reversed: false), -30)
        XCTAssertEqual(scroll.update(motion: .nan, now: 101, enabled: true, speed: 600, reversed: false), 0)
    }
}
