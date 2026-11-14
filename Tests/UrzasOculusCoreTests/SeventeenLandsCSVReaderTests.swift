import Foundation
import XCTest
@testable import UrzasOculusCore

final class SeventeenLandsCSVReaderTests: XCTestCase {
    func testStreamsGzipCSVWithDynamicColumnsAndQuotedFields() throws {
        let compressed = Data(base64Encoded:
            "H4sIAAAAAAAC/8tLzE3VyS9IzcvMS4/PSMxL0UkpSizP41JyTixK0VHwA0or6RjpGHIphZTnKygpBZbml6QWKylxBacm5+elKORk5gEVGOgYcwEAhdNtZkoAAAA="
        )!
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("csv.gz")
        try compressed.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        var capturedHeader: SeventeenLandsCSVHeader?
        var rows: [[String]] = []
        let count = try SeventeenLandsCSVReader.readTable(
            from: file,
            chunkSize: 7,
            onHeader: { capturedHeader = $0 },
            onRow: { rows.append($0) }
        )

        XCTAssertEqual(count, 2)
        XCTAssertEqual(capturedHeader?.columns, ["name", "opening_hand", "drawn"])
        XCTAssertEqual(capturedHeader?.value(for: "drawn", in: rows[0]), "1")
        XCTAssertEqual(rows[0], ["Card, Name", "2", "1"])
        XCTAssertEqual(rows[1], ["Two \"Quotes\"\nSecond line", "0", "3"])
    }

    func testRejectsRowsWithDifferentColumnCounts() throws {
        let compressed = Data(base64Encoded:
            "H4sIAAAAAAAC/0vUSeIy1DHiMuYCANihyAcKAAAA"
        )!
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("csv.gz")
        try compressed.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        XCTAssertThrowsError(try SeventeenLandsCSVReader.readTable(
            from: file,
            onHeader: { _ in },
            onRow: { _ in }
        ))
    }
}
