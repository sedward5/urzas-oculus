import Foundation
import XCTest
@testable import UrzasOculusCore

final class SeventeenLandsCatalogTests: XCTestCase {
    func testParsesCatalogRowsAndUsesPublishedArchiveLinks() throws {
        let html = """
        <table>
          <tr>
            <td>HOB</td>
            <td>PremierDraft</td>
            <td>2026-08-30</td>
            <td><a href="https://17lands-public.s3.amazonaws.com/analysis_data/draft_data_public.HOB.PremierDraft.csv.gz">link</a></td>
            <td><a href="https://17lands-public.s3.amazonaws.com/analysis_data/game_data_public.HOB.PremierDraft.csv.gz">link</a></td>
          </tr>
          <tr>
            <td>HOB</td>
            <td>Sealed</td>
            <td>2026-08-30</td>
            <td>-</td>
            <td><a href="https://17lands-public.s3.amazonaws.com/analysis_data/game_data_public.HOB.Sealed.csv.gz">link</a></td>
          </tr>
        </table>
        """

        let entries = try SeventeenLandsPublicDatasetCatalog.parse(html: html)

        XCTAssertEqual(entries.count, 2)
        let draftEntry = try XCTUnwrap(entries.first { $0.eventType == "PremierDraft" })
        XCTAssertEqual(draftEntry.setCode, "HOB")
        XCTAssertEqual(draftEntry.draftArchiveURL?.lastPathComponent,
                       "draft_data_public.HOB.PremierDraft.csv.gz")
        XCTAssertEqual(draftEntry.gameArchiveURL?.lastPathComponent,
                       "game_data_public.HOB.PremierDraft.csv.gz")
        XCTAssertEqual(draftEntry.dataset(.draft)?.downloadURL, draftEntry.draftArchiveURL)

        let sealedEntry = try XCTUnwrap(entries.first { $0.eventType == "Sealed" })
        XCTAssertNil(sealedEntry.draftArchiveURL)
        XCTAssertEqual(sealedEntry.dataset(.game)?.eventType, "Sealed")
        XCTAssertNil(sealedEntry.dataset(.draft))
    }

    func testIgnoresRowsWithoutPublicDataLinks() throws {
        let html = """
        <table>
          <tr><td>XYZ</td><td>PremierDraft</td><td>2026-01-01</td><td>-</td><td>-</td></tr>
        </table>
        """
        XCTAssertThrowsError(try SeventeenLandsPublicDatasetCatalog.parse(html: html))
    }
}
