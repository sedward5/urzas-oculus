import Foundation
import XCTest
@testable import UrzasOculusCore

final class SeventeenLandsDraftMetricsTests: XCTestCase {
    func testAggregatesLastSeenPerPackAndTakenAtPerPick() throws {
        let header = try SeventeenLandsCSVHeader(columns: [
            "draft_id", "pack_number", "pick_number", "pick", "pick_2",
            "pack_card_Wheel Card", "pack_card_Late Card", "pack_card_Picked Card"
        ])
        let accumulator = try SeventeenLandsDraftMetricsAccumulator(header: header)

        // Pick 9 revisits the pack lane seen at pick 1. The other picks
        // belong to separate circulating packs in the same draft round.
        try accumulator.consume(["draft-a", "0", "0", "Picked Card", "", "1", "0", "0"])
        try accumulator.consume(["draft-a", "0", "1", "Other Card", "", "0", "1", "0"])
        try accumulator.consume(["draft-a", "0", "7", "Other Card", "", "0", "0", "0"])
        try accumulator.consume(["draft-a", "0", "8", "Wheel Card", "", "1", "0", "0"])
        try accumulator.consume(["draft-a", "0", "9", "Late Card", "", "0", "1", "0"])

        // A card in a second pack round is another seen instance.
        try accumulator.consume(["draft-a", "1", "0", "Wheel Card", "", "1", "1", "0"])

        let metrics = Dictionary(uniqueKeysWithValues: accumulator.finish().map { ($0.cardName, $0) })
        let wheel = try XCTUnwrap(metrics["Wheel Card"])
        XCTAssertEqual(wheel.seenCount, 2)
        XCTAssertEqual(try XCTUnwrap(wheel.averageLastSeen), 5.0, accuracy: 0.0001)
        XCTAssertEqual(wheel.pickCount, 2)
        XCTAssertEqual(try XCTUnwrap(wheel.averageTakenAt), 5.0, accuracy: 0.0001)

        let late = try XCTUnwrap(metrics["Late Card"])
        XCTAssertEqual(late.seenCount, 2)
        XCTAssertEqual(try XCTUnwrap(late.averageLastSeen), 5.5, accuracy: 0.0001)
        XCTAssertEqual(late.pickCount, 1)
        XCTAssertEqual(try XCTUnwrap(late.averageTakenAt), 10.0, accuracy: 0.0001)

        let picked = try XCTUnwrap(metrics["Picked Card"])
        XCTAssertEqual(picked.seenCount, 1)
        XCTAssertEqual(picked.pickCount, 1)
        XCTAssertEqual(picked.averageLastSeen, 1.0)
    }

    func testRejectsMissingColumnsAndNegativePickNumbers() throws {
        let missing = try SeventeenLandsCSVHeader(columns: ["draft_id", "pack_number", "pick_number", "pick"])
        XCTAssertThrowsError(try SeventeenLandsDraftMetricsAccumulator(header: missing))

        let header = try SeventeenLandsCSVHeader(columns: [
            "draft_id", "pack_number", "pick_number", "pick", "pack_card_Test Card"
        ])
        let accumulator = try SeventeenLandsDraftMetricsAccumulator(header: header)
        XCTAssertThrowsError(try accumulator.consume(["draft", "0", "-1", "Test Card", "1"]))
    }

    func testImporterMergesDraftAndGameFieldsForSharedSnapshot() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
        let store = try LocalDataStore(url: url)
        defer { try? store.close(); try? FileManager.default.removeItem(at: url) }
        try store.upsert(card: CardRecord(id: "test-printing", name: "Test Card", setCode: "TST"))

        // The production reader intentionally accepts gzip archives only.
        // Keep this integration fixture in the same format as 17Lands exports.
        let compressedDraftCSV = Data(base64Encoded:
            "H4sIAAAAAAAC/0spSkwric9M0SlITM6OzyvNTUot0inIRGVDJJMTi1LiQ1KLSxScgSyuFJBO3UQdAyCEi+oYcgEAa+uWKFIAAAA="
        )!
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("csv.gz")
        try compressedDraftCSV.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let draftSnapshot = try SeventeenLandsDraftMetricsImporter.importCSV(
            from: file,
            request: SeventeenLandsImportRequest(setCode: "TST"),
            snapshotID: "shared-snapshot",
            into: store
        )
        XCTAssertEqual(try store.components(datasetKey: draftSnapshot.datasetKey).map(\.kind), [.draft])
        try store.upsert(performance: CardPerformanceRecord(
            snapshotID: "shared-snapshot",
            setCode: "TST",
            eventType: "PremierDraft",
            cardName: "Test Card",
            gameCount: 12,
            winRate: 0.55
        ))

        let metric = try XCTUnwrap(store.performance(
            setCode: "TST", eventType: "PremierDraft", cardName: "Test Card"
        ))
        XCTAssertEqual(metric.pickCount, 1)
        XCTAssertEqual(metric.seenCount, 1)
        XCTAssertEqual(metric.averageLastSeen, 1.0)
        XCTAssertEqual(metric.gameCount, 12)
        XCTAssertEqual(metric.winRate, 0.55)
    }

    func testSecondaryPickContributesToPickCountAndATA() throws {
        let header = try SeventeenLandsCSVHeader(columns: [
            "draft_id", "pack_number", "pick_number", "pick", "pick_2",
            "pack_card_Primary", "pack_card_Secondary"
        ])
        let accumulator = try SeventeenLandsDraftMetricsAccumulator(header: header)
        // Raw pick_number 3 is the fourth pick in the human-facing ATA metric.
        try accumulator.consume(["draft", "1", "3", "Primary", "Secondary", "1", "1"])
        let values = Dictionary(uniqueKeysWithValues: accumulator.finish().map { ($0.cardName, $0) })
        XCTAssertEqual(values["Secondary"]?.pickCount, 1)
        XCTAssertEqual(values["Secondary"]?.averageTakenAt, 4.0)
    }
}
