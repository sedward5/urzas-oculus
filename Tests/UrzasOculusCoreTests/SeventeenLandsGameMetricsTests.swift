import Foundation
import XCTest
@testable import UrzasOculusCore

final class SeventeenLandsGameMetricsTests: XCTestCase {
    func testAggregatesCopyWeightedGameMetrics() throws {
        let header = try SeventeenLandsCSVHeader(columns: [
            "won", "main_colors",
            "opening_hand_Test Card", "drawn_Test Card", "tutored_Test Card",
            "deck_Test Card", "sideboard_Test Card",
            "opening_hand_Second Card", "drawn_Second Card", "tutored_Second Card",
            "deck_Second Card", "sideboard_Second Card"
        ])
        let accumulator = try SeventeenLandsGameMetricsAccumulator(header: header)
        try accumulator.consume(["true", "WU", "2", "1", "0", "3", "0", "0", "1", "0", "1", "1"])
        try accumulator.consume(["false", "WU", "0", "1", "0", "2", "1", "1", "0", "0", "1", "0"])

        let metrics = Dictionary(uniqueKeysWithValues: accumulator.finish().map { ($0.cardName, $0) })
        let testCard = try XCTUnwrap(metrics["Test Card"])
        XCTAssertEqual(testCard.gameCount, 2)
        XCTAssertEqual(testCard.gamesPlayedCount, 5)
        XCTAssertEqual(try XCTUnwrap(testCard.gamesPlayedWinRate), 0.6, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(testCard.playRate), 5.0 / 6.0, accuracy: 0.0001)
        XCTAssertEqual(testCard.gamesInHandCount, 4)
        XCTAssertEqual(try XCTUnwrap(testCard.gamesInHandWinRate), 0.75, accuracy: 0.0001)
        XCTAssertEqual(testCard.openingHandCount, 2)
        XCTAssertEqual(try XCTUnwrap(testCard.openingHandWinRate), 1.0, accuracy: 0.0001)
        XCTAssertEqual(testCard.drawnCount, 2)
        XCTAssertEqual(try XCTUnwrap(testCard.drawnWinRate), 0.5, accuracy: 0.0001)
        XCTAssertEqual(testCard.gamesNotSeenCount, 1)
        XCTAssertEqual(try XCTUnwrap(testCard.gamesNotSeenWinRate), 0.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(testCard.improvementInHand), 0.75, accuracy: 0.0001)

        let secondCard = try XCTUnwrap(metrics["Second Card"])
        XCTAssertEqual(secondCard.gamesPlayedCount, 2)
        XCTAssertEqual(try XCTUnwrap(secondCard.playRate), 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(secondCard.gamesInHandCount, 2)
        XCTAssertEqual(try XCTUnwrap(secondCard.gamesInHandWinRate), 0.5, accuracy: 0.0001)
    }

    func testColorFilterOnlyIncludesMatchingMainColors() throws {
        let header = try SeventeenLandsCSVHeader(columns: [
            "won", "main_colors", "deck_Test Card", "sideboard_Test Card"
        ])
        let accumulator = try SeventeenLandsGameMetricsAccumulator(header: header, colorFilter: "WU")
        try accumulator.consume(["true", "WU", "2", "0"])
        try accumulator.consume(["false", "BR", "1", "0"])
        let metric = try XCTUnwrap(accumulator.finish().first)
        XCTAssertEqual(metric.gameCount, 1)
        XCTAssertEqual(metric.gamesPlayedCount, 2)
        XCTAssertEqual(try XCTUnwrap(metric.gamesPlayedWinRate), 1.0)
    }

    func testRejectsMissingWinColumnAndInvalidCounts() throws {
        let noWinHeader = try SeventeenLandsCSVHeader(columns: ["deck_Test Card"])
        XCTAssertThrowsError(try SeventeenLandsGameMetricsAccumulator(header: noWinHeader))
        let header = try SeventeenLandsCSVHeader(columns: ["won", "deck_Test Card"])
        let accumulator = try SeventeenLandsGameMetricsAccumulator(header: header)
        XCTAssertThrowsError(try accumulator.consume(["true", "-1"]))
        XCTAssertThrowsError(try accumulator.consume(["maybe", "1"]))
    }

    func testCSVImporterPersistsSnapshotAndCopyWeightedMetrics() throws {
        let (store, dbURL) = try makeStore()
        defer { try? store.close(); try? FileManager.default.removeItem(at: dbURL) }
        try store.upsert(card: CardRecord(id: "test-printing", name: "Test Card", setCode: "TST"))

        let compressed = Data(base64Encoded:
            "H4sIAPnV+GoC/1WKMQ6DMBAEe7+CB2xhkifwBVBK64IPsELuorMR3we5CXQ7M7ur4EtJwqirWob+WJLMYSGJoedcmo4sIhrtcuGyFTW+PXj8XDCnyG8919+5YhvjNeCBFh5PeDfRmqvyVZ3BHb1uiquRAAAA"
        )!
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("csv.gz")
        try compressed.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let snapshot = try SeventeenLandsGameMetricsImporter.importCSV(
            from: file,
            request: SeventeenLandsImportRequest(setCode: "tst"),
            snapshotID: "game-metrics-test",
            into: store
        )
        let metric = try XCTUnwrap(store.performance(
            setCode: "TST", eventType: "PremierDraft", cardName: "Test Card"
        ))
        XCTAssertEqual(snapshot.recordCount, 1)
        XCTAssertEqual(metric.cardScryfallID, "test-printing")
        XCTAssertEqual(metric.gamesPlayedCount, 5)
        XCTAssertEqual(metric.winRate, 0.75)
        XCTAssertEqual(metric.drawnImprovementWinRate, 0.75)
    }

    private func makeStore() throws -> (LocalDataStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
        return (try LocalDataStore(url: url), url)
    }
}
