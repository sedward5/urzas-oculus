import Foundation

public struct SeventeenLandsCatalogEntry: Equatable, Sendable, Identifiable {
    public let setCode: String
    public let eventType: String
    public let lastUpdatedAt: Date
    public let draftArchiveURL: URL?
    public let gameArchiveURL: URL?

    public var id: String { "\(setCode):\(eventType)" }

    public func dataset(_ kind: SeventeenLandsPublicDatasetKind) -> SeventeenLandsPublicDataset? {
        let archiveURL = kind == .draft ? draftArchiveURL : gameArchiveURL
        guard let archiveURL else { return nil }
        return SeventeenLandsPublicDataset(
            setCode: setCode,
            eventType: eventType,
            kind: kind,
            lastUpdatedAt: lastUpdatedAt,
            archiveURL: archiveURL
        )
    }
}

public enum SeventeenLandsCatalogError: Error, Equatable {
    case invalidHTML
    case invalidDatasetDate(String)
}

/// Retrieves and parses the official public dataset listing. Archive URLs
/// come from the page itself; the downloader does not need to guess which
/// datasets exist for a set and event type.
public enum SeventeenLandsPublicDatasetCatalog {
    public static let listingURL = URL(string: "https://www.17lands.com/public_datasets")!

    public static func fetch(
        session: URLSession = .shared
    ) async throws -> [SeventeenLandsCatalogEntry] {
        var request = URLRequest(url: listingURL)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("UrzasOculus/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw SeventeenLandsCatalogError.invalidHTML
        }
        return try parse(html: html, baseURL: listingURL)
    }

    public static func parse(
        html: String,
        baseURL: URL = listingURL
    ) throws -> [SeventeenLandsCatalogEntry] {
        let rows = try matches(pattern: "<tr\\b[^>]*>(.*?)</tr>", in: html)
        var entries: [SeventeenLandsCatalogEntry] = []

        for row in rows {
            let cells = try matches(pattern: "<td\\b[^>]*>(.*?)</td>", in: row)
            guard cells.count >= 3 else { continue }

            let setCode = plainText(cells[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let eventType = plainText(cells[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            let dateText = plainText(cells[2]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !setCode.isEmpty, !eventType.isEmpty,
                  let updatedAt = parseDate(dateText) else { continue }

            var draftURL: URL?
            var gameURL: URL?
            for cell in cells.dropFirst(3) {
                for href in try hrefs(in: cell) {
                    guard let url = URL(string: decodeHTMLEntities(href), relativeTo: baseURL)?.absoluteURL else {
                        continue
                    }
                    guard url.scheme == "https",
                          url.host == "17lands-public.s3.amazonaws.com" else { continue }
                    let filename = url.lastPathComponent.lowercased()
                    if filename.hasPrefix("draft_data_public.") {
                        draftURL = url
                    } else if filename.hasPrefix("game_data_public.") {
                        gameURL = url
                    }
                }
            }

            guard draftURL != nil || gameURL != nil else { continue }
            entries.append(SeventeenLandsCatalogEntry(
                setCode: setCode,
                eventType: eventType,
                lastUpdatedAt: updatedAt,
                draftArchiveURL: draftURL,
                gameArchiveURL: gameURL
            ))
        }

        guard !entries.isEmpty else { throw SeventeenLandsCatalogError.invalidHTML }
        return entries
    }

    private static func matches(pattern: String, in text: String) throws -> [String] {
        let expression = try NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func hrefs(in html: String) throws -> [String] {
        let expression = try NSRegularExpression(
            pattern: "<a\\b[^>]*href\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        let range = NSRange(html.startIndex..., in: html)
        return expression.matches(in: html, range: range).compactMap { match in
            guard let range = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[range])
        }
    }

    private static func plainText(_ html: String) -> String {
        let withoutTags = html.replacingOccurrences(
            of: "<[^>]+>", with: "", options: .regularExpression
        )
        return decodeHTMLEntities(withoutTags)
    }

    private static func decodeHTMLEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}
