import Foundation
import XCTest
@testable import UrzasOculusCore

final class RecommendationServiceTests: XCTestCase {
    private let dataset = RecommendationDatasetRequest(setCode: "TST")
    private let snapshotID = "snapshot-shared"

    func testLoadsCandidatesAndEvaluatesThroughSharedEngine() throws {
        let store = try makeReadyStore()
        defer { try? store.close() }
        try addCard("Strong", id: "strong", rate: 0.70, count: 100, to: store)
        try addCard("Steady", id: "steady", rate: 0.60, count: 100, to: store)
        try addCard("No Metrics", id: "missing-metrics", rate: nil, count: 0, to: store)

        let result = try RecommendationService.evaluate(
            candidateCardIDs: ["steady", "strong", "missing-metrics"],
            dataset: dataset,
            configuration: configuration,
            in: store
        )

        XCTAssertEqual(result.ranked.map(\.cardName), ["Strong", "Steady"])
        XCTAssertEqual(result.excluded.map(\.cardName), ["No Metrics"])
        XCTAssertEqual(result.gameSnapshotID, snapshotID)
    }

    func testRejectsUnknownCandidateCardID() throws {
        let store = try makeReadyStore()
        defer { try? store.close() }

        XCTAssertThrowsError(try RecommendationService.evaluate(
            candidateCardIDs: ["not-in-store"],
            dataset: dataset,
            configuration: configuration,
            in: store
        )) {
            XCTAssertEqual(
                $0 as? RecommendationServiceError,
                .missingCardRecord("not-in-store")
            )
        }
    }

    func testRejectsDuplicateCandidateIDs() throws {
        let store = try makeReadyStore()
        defer { try? store.close() }

        XCTAssertThrowsError(try RecommendationService.evaluate(
            candidateCardIDs: ["same", "same"],
            dataset: dataset,
            configuration: configuration,
            in: store
        )) {
            XCTAssertEqual(
                $0 as? RecommendationServiceError,
                .duplicateCandidateID("same")
            )
        }
    }

    func testReadinessIsCheckedBeforeCandidateLookup() throws {
        let store = try makeReadyStore(includeDraft: false)
        defer { try? store.close() }

        XCTAssertThrowsError(try RecommendationService.evaluate(
            candidateCardIDs: ["missing-card"],
            dataset: dataset,
            configuration: configuration,
            in: store
        )) {
            guard case RecommendationEngineError.datasetNotReady = $0 else {
                return XCTFail("Unexpected error: \($0)")
            }
        }
    }

    private var configuration: RecommendationScoringConfiguration {
        RecommendationScoringConfiguration(
            version: "service-test",
            baselineDatasetKey: dataset.datasetKey,
            baselineSnapshotID: snapshotID,
            baselineWinRate: 0.55,
            priorWeight: 40
        )
    }

    private func makeReadyStore(includeDraft: Bool = true) throws -> LocalDataStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        let store = try LocalDataStore(url: url)
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        try store.save(snapshot: DatasetSnapshot(
            id: snapshotID,
            source: .seventeenLands,
            datasetKey: dataset.datasetKey,
            sourceUpdatedAt: timestamp,
            importedAt: timestamp,
            recordCount: 10,
            attribution: SeventeenLandsImporter.attribution
        ))
        try store.save(component: DatasetComponentSnapshot(
            datasetKey: dataset.datasetKey,
            kind: .game,
            snapshotID: snapshotID,
            sourceUpdatedAt: timestamp,
            importedAt: timestamp,
            recordCount: 10
        ))
        if includeDraft {
            try store.save(component: DatasetComponentSnapshot(
                datasetKey: dataset.datasetKey,
                kind: .draft,
                snapshotID: snapshotID,
                sourceUpdatedAt: timestamp,
                importedAt: timestamp,
                recordCount: 10
            ))
        }
        return store
    }

    private func addCard(
        _ name: String,
        id: String,
        rate: Double?,
        count: Int,
        to store: LocalDataStore
    ) throws {
        try store.upsert(card: CardRecord(id: id, name: name, setCode: "TST"))
        try store.upsert(performance: CardPerformanceRecord(
            snapshotID: snapshotID,
            setCode: "TST",
            eventType: "PremierDraft",
            userGroup: "all",
            colorFilter: nil,
            cardName: name,
            cardScryfallID: id,
            winRate: rate,
            gamesInHandCount: count
        ))
    }
}
