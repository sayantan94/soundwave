import XCTest
@testable import SoundWaveCore

final class ControlAccessTests: XCTestCase {
    func testGrantingAccessibilityDoesNotEnableControlWithStaleEventDenial() {
        XCTAssertEqual(ControlAccess(accessibilityGranted: false, eventPostingGranted: false), .permissionNeeded)
        XCTAssertEqual(ControlAccess(accessibilityGranted: true, eventPostingGranted: false), .restartNeeded)
        XCTAssertEqual(ControlAccess(accessibilityGranted: true, eventPostingGranted: true), .ready)
    }

    func testRevokingAccessibilityDisablesControlDespiteCachedPostingGrant() {
        XCTAssertEqual(ControlAccess(accessibilityGranted: false, eventPostingGranted: true), .permissionNeeded)
    }
}
