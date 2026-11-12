import XCTest
@testable import UrzasOculusCore

final class ProjectMetadataTests: XCTestCase {
    func testProjectMetadata() {
        XCTAssertEqual(ProjectMetadata.name, "Urza's Oculus")
        XCTAssertEqual(ProjectMetadata.bundleIdentifier, "com.local.urzas-oculus")
        XCTAssertEqual(ProjectMetadata.minimumMacOSVersion, "14.0")
    }
}
