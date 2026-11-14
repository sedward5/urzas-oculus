import Foundation

public enum SeventeenLandsPublicDatasetKind: String, Codable, Sendable {
    case draft
    case game
}

/// One official 17Lands public CSV archive.
public struct SeventeenLandsPublicDataset: Equatable, Sendable {
    public let setCode: String
    public let eventType: String
    public let kind: SeventeenLandsPublicDatasetKind
    public let lastUpdatedAt: Date?
    public let archiveURL: URL?

    public init(
        setCode: String,
        eventType: String = "PremierDraft",
        kind: SeventeenLandsPublicDatasetKind,
        lastUpdatedAt: Date? = nil,
        archiveURL: URL? = nil
    ) {
        self.setCode = setCode.uppercased()
        self.eventType = eventType
        self.kind = kind
        self.lastUpdatedAt = lastUpdatedAt
        self.archiveURL = archiveURL
    }

    /// Prefer the exact URL supplied by the official catalog. The naming
    /// convention remains a fallback for explicitly constructed descriptors.
    public var downloadURL: URL {
        if let archiveURL { return archiveURL }
        let filename = "\(kind.rawValue)_data_public.\(setCode).\(eventType).csv.gz"
        return URL(string: "https://17lands-public.s3.amazonaws.com/analysis_data/\(filename)")!
    }

    public var datasetKey: String {
        "\(setCode):\(eventType):\(kind.rawValue)"
    }
}

public struct SeventeenLandsDownloadReceipt: Equatable, Sendable {
    public let dataset: SeventeenLandsPublicDataset
    public let localURL: URL
    public let downloadedAt: Date
    public let sourceUpdatedAt: Date?
    public let etag: String?
    public let byteCount: Int64
}

public enum SeventeenLandsDownloadError: Error, Equatable {
    case invalidResponse
    case httpStatus(Int)
}

/// Downloads one explicitly selected public archive. Discovery, freshness
/// policy, decompression, and aggregation are separate responsibilities.
public enum SeventeenLandsPublicDatasetDownloader {
    public static func download(
        _ dataset: SeventeenLandsPublicDataset,
        to destination: URL,
        now: Date = .now
    ) async throws -> SeventeenLandsDownloadReceipt {
        var request = URLRequest(url: dataset.downloadURL)
        request.setValue("UrzasOculus/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/gzip, application/octet-stream", forHTTPHeaderField: "Accept")

        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw SeventeenLandsDownloadError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw SeventeenLandsDownloadError.httpStatus(response.statusCode)
        }

        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let backupURL = destination.appendingPathExtension("previous-\(UUID().uuidString)")
        let hadPreviousFile = FileManager.default.fileExists(atPath: destination.path)
        if hadPreviousFile {
            try FileManager.default.moveItem(at: destination, to: backupURL)
        }
        do {
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
            if hadPreviousFile {
                try? FileManager.default.removeItem(at: backupURL)
            }
        } catch {
            if hadPreviousFile {
                try? FileManager.default.moveItem(at: backupURL, to: destination)
            }
            throw error
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let remoteLastModified = parseHTTPDate(
            response.value(forHTTPHeaderField: "Last-Modified")
        )

        return SeventeenLandsDownloadReceipt(
            dataset: dataset,
            localURL: destination,
            downloadedAt: now,
            sourceUpdatedAt: dataset.lastUpdatedAt ?? remoteLastModified,
            etag: response.value(forHTTPHeaderField: "ETag"),
            byteCount: byteCount
        )
    }

    private static func parseHTTPDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: value)
    }
}
