import Foundation
import XCTest
@testable import UrzasOculusCore

final class DatasetFreshnessTests: XCTestCase {
    func testFreshnessSeparatesAcquisitionAgeFromSourceDataAge() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let publishedAt = now.addingTimeInterval(-10 * 86_400)
        let acquiredAt = now.addingTimeInterval(-2 * 86_400)
        let snapshot = DatasetSnapshot(
            id: "17lands-fra-premier",
            source: .seventeenLands,
            datasetKey: "FRA:PremierDraft:all:all",
            sourceUpdatedAt: publishedAt,
            importedAt: acquiredAt,
            recordCount: 100,
            attribution: "17Lands"
        )

        let freshness = snapshot.freshness(at: now)

        XCTAssertEqual(freshness.acquisitionAge, 2 * 86_400, accuracy: 0.001)
        XCTAssertEqual(freshness.sourceDataAge ?? -1, 10 * 86_400, accuracy: 0.001)
        XCTAssertEqual(freshness.acquisitionAgeDays, 2, accuracy: 0.001)
        XCTAssertEqual(freshness.sourceDataAgeDays ?? -1, 10, accuracy: 0.001)
    }

    func testFreshnessAllowsUnknownUpstreamUpdateDate() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let snapshot = DatasetSnapshot(
            id: "17lands-unknown-date",
            source: .seventeenLands,
            datasetKey: "FRA:PremierDraft:all:all",
            importedAt: now.addingTimeInterval(-3_600),
            recordCount: 10,
            attribution: "17Lands"
        )

        let freshness = snapshot.freshness(at: now)

        XCTAssertEqual(freshness.acquisitionAge, 3_600, accuracy: 0.001)
        XCTAssertNil(freshness.sourceDataAge)
    }
}
