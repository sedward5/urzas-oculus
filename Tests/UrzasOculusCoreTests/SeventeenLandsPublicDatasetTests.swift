import Foundation
import XCTest
@testable import UrzasOculusCore

final class SeventeenLandsPublicDatasetTests: XCTestCase {
    func testOfficialPublicArchiveURLsAndDatasetKeys() {
        let publishedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let draft = SeventeenLandsPublicDataset(
            setCode: "fra", eventType: "PremierDraft",
            kind: .draft, lastUpdatedAt: publishedAt
        )
        let game = SeventeenLandsPublicDataset(
            setCode: "FRA", eventType: "PremierDraft", kind: .game
        )

        XCTAssertEqual(
            draft.downloadURL.absoluteString,
            "https://17lands-public.s3.amazonaws.com/analysis_data/draft_data_public.FRA.PremierDraft.csv.gz"
        )
        XCTAssertEqual(
            game.downloadURL.absoluteString,
            "https://17lands-public.s3.amazonaws.com/analysis_data/game_data_public.FRA.PremierDraft.csv.gz"
        )
        XCTAssertEqual(draft.datasetKey, "FRA:PremierDraft:draft")
        XCTAssertEqual(game.datasetKey, "FRA:PremierDraft:game")
        XCTAssertEqual(draft.lastUpdatedAt, publishedAt)
    }
}
