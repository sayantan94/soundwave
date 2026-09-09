import CoreGraphics
import XCTest
@testable import SoundWaveCore

final class KeyboardModifiersTests: XCTestCase {
    func testDesktopArrowsMatchMacOSFunctionArrowShortcutFlags() {
        // Control (0x040000) + numeric pad (0x200000) + function (0x800000).
        for key: CGKeyCode in [123, 124] {
            XCTAssertEqual(KeyboardModifiers.forKey(key, modifiers: .maskControl).rawValue, 0xA40000)
        }
    }

    func testModifierKeysAndAppSwitchingDoNotAcquireArrowFlags() {
        XCTAssertEqual(KeyboardModifiers.forKey(59, modifiers: .maskControl), .maskControl)
        XCTAssertEqual(KeyboardModifiers.forKey(48, modifiers: [.maskCommand, .maskShift]), [.maskCommand, .maskShift])
    }
}
