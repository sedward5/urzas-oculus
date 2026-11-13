import Foundation
import XCTest
@testable import UrzasOculusCore

final class DataEngineTests: XCTestCase {
    private func makeStore() throws -> (LocalDataStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
        return (try LocalDataStore(url: url), url)
    }

    func testScryfallJSONLinesImportPreservesIdentityAndFaces() throws {
        let (store, dbURL) = try makeStore()
        defer { try? store.close(); try? FileManager.default.removeItem(at: dbURL) }
        let json = """
        {"id":"printing-1","oracle_id":"oracle-1","arena_id":123,"name":"Front // Back","set":"tst","set_name":"Test Set","collector_number":"1","rarity":"rare","layout":"transform","mana_cost":"{1}{G}","cmc":2,"type_line":"Creature — Human","oracle_text":"Front text","colors":["G"],"color_identity":["G"],"keywords":["Trample"],"card_faces":[{"name":"Front","mana_cost":"{1}{G}","type_line":"Creature","oracle_text":"Front text","power":"2","toughness":"2"},{"name":"Back","type_line":"Creature","oracle_text":"Back text","power":"3","toughness":"3"}]}
        """
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try (json + "\n").write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let snapshot = try ScryfallImporter.importJSONLines(from: file, snapshotID: "scryfall-test", into: store)
        let card = try XCTUnwrap(store.card(arenaID: 123))
        XCTAssertEqual(snapshot.recordCount, 1)
        XCTAssertEqual(card.id, "printing-1")
        XCTAssertEqual(card.oracleID, "oracle-1")
        XCTAssertEqual(card.setCode, "TST")
        XCTAssertEqual(card.cardFaces.map(\.name), ["Front", "Back"])
    }

    func testNameLookupIsSetScopedAndCaseInsensitive() throws {
        let (store, url) = try makeStore()
        defer { try? store.close(); try? FileManager.default.removeItem(at: url) }
        try store.upsert(card: CardRecord(id: "a", name: "Lightning Bolt", setCode: "M10"))
        try store.upsert(card: CardRecord(id: "b", name: "Lightning Bolt", setCode: "STA"))
        XCTAssertEqual(try store.cards(named: "LIGHTNING BOLT", setCode: "sta").map(\.id), ["b"])
        XCTAssertEqual(try store.cards(named: "Lightning Bolt").count, 2)
    }

    func testSeventeenLandsImportLinksMetricsAndPreservesContext() throws {
        let (store, url) = try makeStore()
        defer { try? store.close(); try? FileManager.default.removeItem(at: url) }
        try store.save(snapshot: DatasetSnapshot(id: "scryfall", source: .scryfall,
            datasetKey: "default_cards", recordCount: 1, attribution: "Scryfall"))
        try store.upsert(card: CardRecord(id: "printing-id", oracleID: "oracle-id",
            arenaID: 42, name: "Test Creature", setCode: "TST"))
        let json = """
        [{"name":"Test Creature","color":"G","rarity":"common","game_count":1200,"pick_count":900,"play_rate":0.45,"win_rate":0.57,"opening_hand_win_rate":0.55,"drawn_win_rate":0.58,"drawn_improvement_win_rate":0.08,"avg_seen":7.2,"avg_pick":5.1}]
        """
        let request = SeventeenLandsImportRequest(setCode: "tst", userGroup: "top")
        let snapshot = try SeventeenLandsImporter.importJSON(Data(json.utf8), request: request,
            snapshotID: "17lands-test", into: store)
        let metric = try XCTUnwrap(store.performance(setCode: "TST", eventType: "PremierDraft",
            cardName: "test creature", userGroup: "top"))
        XCTAssertEqual(snapshot.recordCount, 1)
        XCTAssertEqual(metric.cardScryfallID, "printing-id")
        XCTAssertEqual(metric.winRate, 0.57)
        XCTAssertEqual(metric.drawnImprovementWinRate, 0.08)
        XCTAssertEqual(metric.averageLastSeen, 7.2)
    }

    func testSeventeenLandsURLIncludesFilters() throws {
        let request = SeventeenLandsImportRequest(setCode: "tst", userGroup: "top", colorFilter: "WU")
        let url = try XCTUnwrap(request.url)
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).compactMap {
            guard let value = $0.value else { return nil }
            return ($0.name, value)
        })
        XCTAssertEqual(query["expansion"], "TST")
        XCTAssertEqual(query["format"], "PremierDraft")
        XCTAssertEqual(query["user_group"], "top")
        XCTAssertEqual(query["colors"], "WU")
    }

    func testArenaIDLookupDoesNotGuessAcrossPrintings() throws {
        let (store, url) = try makeStore()
        defer { try? store.close(); try? FileManager.default.removeItem(at: url) }
        try store.upsert(card: CardRecord(id: "printing-a", arenaID: 77,
            name: "Example Card", setCode: "AAA"))
        try store.upsert(card: CardRecord(id: "printing-b", arenaID: 77,
            name: "Example Card", setCode: "BBB"))

        XCTAssertEqual(try store.cards(arenaID: 77).count, 2)
        XCTAssertNil(try store.card(arenaID: 77))
        XCTAssertEqual(try store.card(arenaID: 77, setCode: "bbb")?.id, "printing-b")
    }

    func testPerformanceRequiresSnapshotForeignKey() throws {
        let (store, url) = try makeStore()
        defer { try? store.close(); try? FileManager.default.removeItem(at: url) }
        let metric = CardPerformanceRecord(snapshotID: "missing", setCode: "TST",
            eventType: "PremierDraft", cardName: "No Snapshot", winRate: 0.5)
        XCTAssertThrowsError(try store.upsert(performance: metric))
    }
}
