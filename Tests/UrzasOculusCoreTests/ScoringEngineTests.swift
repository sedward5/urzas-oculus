import Foundation
import XCTest
@testable import UrzasOculusCore

final class ScoringEngineTests: XCTestCase {
    private let dataset = RecommendationDatasetRequest(setCode: "TST")

    func testRanksByRegularizedGamesInHandWinRate() throws {
        let request = try makeRequest(candidates: [
            candidate("Strong", rate: 0.70, count: 100, alsa: 2.1, ata: 3.4),
            candidate("Small Sample", rate: 0.90, count: 5),
            candidate("Steady", rate: 0.60, count: 100)
        ])

        let result = try ScoringEngine.evaluate(request)

        XCTAssertEqual(result.ranked.map(\.cardName), ["Strong", "Small Sample", "Steady"])
        let strongest = try XCTUnwrap(result.ranked.first)
        XCTAssertEqual(strongest.score, (0.70 * 100 + 0.55 * 40) / 140, accuracy: 0.000001)
        XCTAssertEqual(strongest.averageLastSeen, 2.1)
        XCTAssertEqual(strongest.averageTakenAt, 3.4)
        XCTAssertTrue(strongest.explanation.contains("copy-weighted observations"))
        XCTAssertEqual(result.engineVersion, ScoringEngine.engineVersion)
        XCTAssertEqual(result.scoringConfigurationVersion, "baseline-test")
        XCTAssertEqual(result.gameSnapshotID, "snapshot-1")
    }

    func testIdenticalInputsProduceIdenticalResults() throws {
        let request = try makeRequest(candidates: [
            candidate("Alpha", rate: 0.61, count: 42),
            candidate("Beta", rate: 0.61, count: 42)
        ])

        XCTAssertEqual(
            try ScoringEngine.evaluate(request),
            try ScoringEngine.evaluate(request)
        )
        XCTAssertEqual(try ScoringEngine.evaluate(request).ranked.map(\.cardName), ["Alpha", "Beta"])
    }

    func testRecommendationResultRoundTripsThroughJSON() throws {
        let request = try makeRequest(candidates: [
            candidate("Artifact", rate: 0.64, count: 75, alsa: 3.2, ata: 4.1)
        ])
        let result = try ScoringEngine.evaluate(request)
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(RecommendationResult.self, from: data)

        XCTAssertEqual(decoded, result)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.scoringConfigurationVersion, "baseline-test")
    }

    func testRejectsUnreadyDataset() throws {
        let request = try makeRequest(
            candidates: [candidate("Card", rate: 0.6, count: 20)],
            ready: false
        )
        XCTAssertThrowsError(try ScoringEngine.evaluate(request)) { error in
            guard case RecommendationEngineError.datasetNotReady = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testExcludesMissingAndMismatchedCandidateData() throws {
        let request = try makeRequest(candidates: [
            RecommendationCandidateInput(
                card: CardRecord(id: "missing", name: "Missing", setCode: "TST"),
                performance: nil
            ),
            candidate("Wrong Snapshot", rate: 0.6, count: 20, snapshotID: "old-snapshot"),
            candidate("Wrong Scope", rate: 0.6, count: 20, eventType: "TradDraft"),
            candidate("No Sample", rate: nil, count: 0),
            candidate("Valid", rate: 0.62, count: 40)
        ])

        let result = try ScoringEngine.evaluate(request)

        XCTAssertEqual(result.ranked.map(\.cardName), ["Valid"])
        XCTAssertEqual(result.excluded.count, 4)
        XCTAssertEqual(result.excluded.first(where: { $0.cardName == "Missing" })?.reason, .missingPerformance)
        XCTAssertEqual(result.excluded.first(where: { $0.cardName == "Wrong Snapshot" })?.reason, .mismatchedSnapshot)
        XCTAssertEqual(result.excluded.first(where: { $0.cardName == "Wrong Scope" })?.reason, .mismatchedDatasetScope)
        XCTAssertEqual(result.excluded.first(where: { $0.cardName == "No Sample" })?.reason, .missingGamesInHandSample)
    }

    func testReturnsExplicitExclusionsWhenNoCandidateCanBeScored() throws {
        let request = try makeRequest(candidates: [
            candidate("No Metrics", rate: nil, count: 0)
        ])

        let result = try ScoringEngine.evaluate(request)

        XCTAssertFalse(result.hasRecommendations)
        XCTAssertTrue(result.ranked.isEmpty)
        XCTAssertEqual(result.excluded.map(\.reason), [.missingGamesInHandSample])
    }

    func testRejectsPerformanceForAnotherCardIdentity() throws {
        let card = CardRecord(id: "card-id", name: "Actual Card", setCode: "TST")
        let performance = CardPerformanceRecord(
            snapshotID: "snapshot-1",
            setCode: "TST",
            eventType: "PremierDraft",
            cardName: "Different Card",
            winRate: 0.65,
            gamesInHandCount: 20
        )
        let request = try makeRequest(candidates: [
            RecommendationCandidateInput(card: card, performance: performance)
        ])

        let result = try ScoringEngine.evaluate(request)

        XCTAssertFalse(result.hasRecommendations)
        XCTAssertEqual(result.excluded.first?.reason, .mismatchedDatasetScope)
    }

    func testRejectsMismatchedReadinessScopeAndInvalidConfiguration() throws {
        let ready = try makeReadiness()
        let wrongScope = RecommendationEvaluationRequest(
            dataset: RecommendationDatasetRequest(setCode: "OTHER"),
            readiness: ready,
            candidates: [candidate("Card", rate: 0.6, count: 20)],
            configuration: configuration
        )
        XCTAssertThrowsError(try ScoringEngine.evaluate(wrongScope)) {
            XCTAssertEqual($0 as? RecommendationEngineError, .readinessScopeMismatch)
        }

        let invalid = RecommendationEvaluationRequest(
            dataset: dataset,
            readiness: ready,
            candidates: [candidate("Card", rate: 0.6, count: 20)],
            configuration: RecommendationScoringConfiguration(
                version: "test", baselineWinRate: 1.2, priorWeight: 40
            )
        )
        XCTAssertThrowsError(try ScoringEngine.evaluate(invalid)) {
            XCTAssertEqual($0 as? RecommendationEngineError, .invalidConfiguration)
        }
    }

    private var configuration: RecommendationScoringConfiguration {
        RecommendationScoringConfiguration(
            version: "baseline-test", baselineWinRate: 0.55, priorWeight: 40
        )
    }

    private func makeRequest(
        candidates: [RecommendationCandidateInput],
        ready: Bool = true
    ) throws -> RecommendationEvaluationRequest {
        RecommendationEvaluationRequest(
            dataset: dataset,
            readiness: try makeReadiness(ready: ready),
            candidates: candidates,
            configuration: configuration
        )
    }

    private func makeReadiness(ready: Bool = true) throws -> RecommendationDataReadiness {
        var components = [
            DatasetComponentSnapshot(
                datasetKey: dataset.datasetKey, kind: .game, snapshotID: "snapshot-1",
                sourceUpdatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                importedAt: Date(timeIntervalSince1970: 1_800_000_000), recordCount: 10
            ),
            DatasetComponentSnapshot(
                datasetKey: dataset.datasetKey, kind: .draft, snapshotID: "snapshot-1",
                sourceUpdatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                importedAt: Date(timeIntervalSince1970: 1_800_000_000), recordCount: 10
            )
        ]
        if !ready {
            components.removeAll { $0.kind == .draft }
        }
        return RecommendationDataReadiness(request: dataset, components: components)
    }

    private func candidate(
        _ name: String,
        rate: Double?,
        count: Int,
        alsa: Double? = nil,
        ata: Double? = nil,
        snapshotID: String = "snapshot-1",
        eventType: String = "PremierDraft"
    ) -> RecommendationCandidateInput {
        let card = CardRecord(id: "id-\(name)", name: name, setCode: "TST")
        let performance = CardPerformanceRecord(
            snapshotID: snapshotID,
            setCode: "TST",
            eventType: eventType,
            cardName: name,
            winRate: rate,
            averageLastSeen: alsa,
            averageTakenAt: ata,
            gamesInHandCount: count
        )
        return RecommendationCandidateInput(card: card, performance: performance)
    }
}
