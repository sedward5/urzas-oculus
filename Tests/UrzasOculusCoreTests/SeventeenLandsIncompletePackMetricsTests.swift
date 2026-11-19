import XCTest
@testable import UrzasOculusCore

final class SeventeenLandsIncompletePackMetricsTests: XCTestCase {
    func testKnownPicksAreSeenWhenPackContentsAreMissingOrOmitThePick() throws {
        let header = try SeventeenLandsCSVHeader(columns: [
            "draft_id", "pack_number", "pick_number", "pick", "pick_2",
            "pack_card_Observed Card"
        ])
        let accumulator = try SeventeenLandsDraftMetricsAccumulator(header: header)

        // P1P1 has no reported pack contents, but its known pick is still seen.
        try accumulator.consume(["draft-a", "0", "0", "Known P1P1 Pick", "", "0"])

        // A later row reports other pack contents but omits both known picks.
        try accumulator.consume(["draft-a", "1", "4", "Known Primary", "Known Secondary", "1"])

        let metrics = Dictionary(uniqueKeysWithValues: accumulator.finish().map { ($0.cardName, $0) })

        let p1p1 = try XCTUnwrap(metrics["Known P1P1 Pick"])
        XCTAssertEqual(p1p1.seenCount, 1)
        XCTAssertEqual(p1p1.averageLastSeen, 1.0)
        XCTAssertEqual(p1p1.pickCount, 1)
        XCTAssertEqual(p1p1.averageTakenAt, 1.0)

        for name in ["Known Primary", "Known Secondary"] {
            let metric = try XCTUnwrap(metrics[name])
            XCTAssertEqual(metric.seenCount, 1)
            XCTAssertEqual(metric.averageLastSeen, 5.0)
            XCTAssertEqual(metric.pickCount, 1)
            XCTAssertEqual(metric.averageTakenAt, 5.0)
        }

        let observed = try XCTUnwrap(metrics["Observed Card"])
        XCTAssertEqual(observed.seenCount, 1)
        XCTAssertEqual(observed.averageLastSeen, 5.0)
        XCTAssertEqual(observed.pickCount, 0)
    }
}
