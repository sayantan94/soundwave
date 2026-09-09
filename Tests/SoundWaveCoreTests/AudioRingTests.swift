import CAudioRing
import XCTest

final class AudioRingTests: XCTestCase {
    func testWraparoundKeepsSamplesAndTheirTimestamps() {
        let ring = SWAudioRingCreate(8)!
        defer { SWAudioRingDestroy(ring) }
        var output = [Float](repeating: 0, count: 8); var time = 0.0
        (0..<6).map(Float.init).withUnsafeBufferPointer { SWAudioRingWrite(ring, $0.baseAddress!, 6, 1, 10, 10) }
        XCTAssertEqual(SWAudioRingRead(ring, &output, 4, &time), 4)
        XCTAssertEqual(Array(output.prefix(4)), [0, 1, 2, 3])
        XCTAssertEqual(time, 10.4, accuracy: 0.0001)
        (6..<12).map(Float.init).withUnsafeBufferPointer { SWAudioRingWrite(ring, $0.baseAddress!, 6, 1, 10.6, 10) }
        XCTAssertEqual(SWAudioRingRead(ring, &output, 8, &time), 8)
        XCTAssertEqual(output, Array(4..<12).map(Float.init))
        XCTAssertEqual(time, 11.2, accuracy: 0.0001)
        XCTAssertEqual(SWAudioRingAvailable(ring), 0)
    }
    func testOverflowDropsWholeBlockWithoutOverwritingUnreadAudio() {
        let ring = SWAudioRingCreate(4)!
        defer { SWAudioRingDestroy(ring) }
        let input: [Float] = [1, 2, 3]
        input.withUnsafeBufferPointer { SWAudioRingWrite(ring, $0.baseAddress!, 3, 1, 0, 48000) }
        input.withUnsafeBufferPointer { SWAudioRingWrite(ring, $0.baseAddress!, 3, 1, 1, 48000) }
        XCTAssertEqual(SWAudioRingDropped(ring), 3)
        var output = [Float](repeating: 0, count: 4); var time = 0.0
        XCTAssertEqual(SWAudioRingRead(ring, &output, 4, &time), 3)
        XCTAssertEqual(Array(output.prefix(3)), input)
    }
    func testInterleavedInputSelectsOneChannel() {
        let ring = SWAudioRingCreate(8)!
        defer { SWAudioRingDestroy(ring) }
        let input: [Float] = [1, 101, 2, 102, 3, 103]
        input.withUnsafeBufferPointer { SWAudioRingWrite(ring, $0.baseAddress!, 3, 2, 0, 48000) }
        var output = [Float](repeating: 0, count: 3); var time = 0.0
        XCTAssertEqual(SWAudioRingRead(ring, &output, 3, &time), 3)
        XCTAssertEqual(output, [1, 2, 3])
    }
}
