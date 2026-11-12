import XCTest
@testable import UrzasOculusCore

final class CaptureWindowTests: XCTestCase {
    func testIdentifiesIPhoneMirroringByApplicationName() {
        XCTAssertTrue(
            CaptureWindow.isMirroringCandidate(
                ownerName: "iPhone Mirroring",
                windowTitle: "Steve's iPhone",
                bundleIdentifier: "com.apple.example"
            )
        )
    }

    func testIdentifiesIPhoneMirroringByWindowTitle() {
        XCTAssertTrue(
            CaptureWindow.isMirroringCandidate(
                ownerName: "Some Application",
                windowTitle: "iPhone Mirroring",
                bundleIdentifier: "com.example.app"
            )
        )
    }

    func testIdentifiesScreenContinuityBundle() {
        XCTAssertTrue(
            CaptureWindow.isMirroringCandidate(
                ownerName: "Some Application",
                windowTitle: "Connected Device",
                bundleIdentifier: "com.apple.ScreenContinuity"
            )
        )
    }

    func testDoesNotFlagUnrelatedWindows() {
        XCTAssertFalse(
            CaptureWindow.isMirroringCandidate(
                ownerName: "Safari",
                windowTitle: "Magic: The Gathering",
                bundleIdentifier: "com.apple.Safari"
            )
        )
    }
}
