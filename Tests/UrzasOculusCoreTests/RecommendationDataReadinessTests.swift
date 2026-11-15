import Foundation
import XCTest
@testable import UrzasOculusCore

final class RecommendationDataReadinessTests: XCTestCase {
    private let request = RecommendationDatasetRequest(
        setCode: "tst", eventType: "PremierDraft", userGroup: "all"
    )

    private func component(_ kind: DatasetComponentKind, updatedAt: Date? = Date(timeIntervalSince1970: 1_800_000_000),
                           importedAt: Date = Date(timeIntervalSince1970: 1_800_000_000),
                           count: Int = 10) -> DatasetComponentSnapshot {
        DatasetComponentSnapshot(
            datasetKey: request.datasetKey, kind: kind, snapshotID: "snapshot-shared",
            sourceUpdatedAt: updatedAt, importedAt: importedAt, recordCount: count
        )
    }

    func testRequiresBothGameAndDraftComponents() {
        let result = RecommendationDataReadiness(
            request: request, components: [component(.game)]
        )
        XCTAssertFalse(result.isReady)
        XCTAssertTrue(result.issues.contains(.missingComponent(.draft)))
    }

    func testMatchingNonemptyComponentsAreReady() {
        let result = RecommendationDataReadiness(
            request: request, components: [component(.game), component(.draft)]
        )
        XCTAssertTrue(result.isReady)
    }

    func testRejectsComponentsFromDifferentSnapshots() {
        let game = component(.game)
        let draft = DatasetComponentSnapshot(
            datasetKey: request.datasetKey, kind: .draft, snapshotID: "different-snapshot",
            sourceUpdatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            importedAt: Date(timeIntervalSince1970: 1_800_000_000), recordCount: 10
        )
        let result = RecommendationDataReadiness(request: request, components: [game, draft])
        XCTAssertFalse(result.isReady)
        XCTAssertTrue(result.issues.contains(.mismatchedSnapshot))
    }

    func testRejectsMismatchedSourceUpdateTimes() {
        let game = component(.game)
        let draft = component(.draft, updatedAt: Date(timeIntervalSince1970: 1_800_000_001))
        let result = RecommendationDataReadiness(request: request, components: [game, draft])
        XCTAssertFalse(result.isReady)
        XCTAssertTrue(result.issues.contains(.mismatchedSourceUpdate))
    }

    func testRejectsEmptyAndStaleComponents() {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let game = component(.game, updatedAt: Date(timeIntervalSince1970: 1_700_000_000), count: 0)
        let draft = component(.draft, updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let result = RecommendationDataReadiness(
            request: request, components: [game, draft], now: now,
            maximumSourceAge: 1_000, maximumAcquisitionAge: 1_000
        )
        XCTAssertTrue(result.issues.contains(.emptyComponent(.game)))
        XCTAssertTrue(result.issues.contains(.staleComponent(.game)))
        XCTAssertTrue(result.issues.contains(.staleComponent(.draft)))
    }

    func testUnknownSourceTimestampsBlockReadiness() {
        let result = RecommendationDataReadiness(
            request: request,
            components: [component(.game, updatedAt: nil), component(.draft, updatedAt: nil)]
        )
        XCTAssertFalse(result.isReady)
        XCTAssertTrue(result.issues.contains(.unknownSourceUpdate))
    }

    func testRejectsUnsupportedUserGroup() {
        let topPlayers = RecommendationDatasetRequest(
            setCode: "TST", eventType: "PremierDraft", userGroup: "top"
        )
        let result = RecommendationDataReadiness(
            request: topPlayers, components: []
        )
        XCTAssertTrue(result.issues.contains(.unsupportedUserGroup("top")))
    }

    func testComponentProvenancePersistsIndependently() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
        let store = try LocalDataStore(url: url)
        defer { try? store.close(); try? FileManager.default.removeItem(at: url) }

        let game = component(.game)
        let draft = component(.draft)
        try store.save(component: game)
        try store.save(component: draft)

        let loaded = try store.components(datasetKey: request.datasetKey)
        XCTAssertEqual(Set(loaded.map(\.kind)), Set([.game, .draft]))
        XCTAssertEqual(loaded.first(where: { $0.kind == .game })?.snapshotID, game.snapshotID)
        XCTAssertEqual(loaded.first(where: { $0.kind == .draft })?.recordCount, draft.recordCount)
    }
}
