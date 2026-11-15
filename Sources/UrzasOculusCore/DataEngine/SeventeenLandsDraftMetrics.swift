import Foundation

/// Draft-level statistics derived from the official one-row-per-pick archive.
/// Counts represent card instances, not the number of rows in which a card
/// appeared. ALSA is finalized once per pack; ATA is accumulated per pick.
public struct SeventeenLandsDraftMetric: Equatable, Sendable {
    public let cardName: String
    public let seenCount: Int
    public let averageLastSeen: Double?
    public let pickCount: Int
    public let averageTakenAt: Double?
}

private struct SeventeenLandsDraftTotals {
    var seenCount = 0
    var lastSeenPickSum = 0
    var pickCount = 0
    var takenAtPickSum = 0
}

/// Streaming accumulator for the wide 17Lands draft CSV.
///
/// The archive is ordered by draft and pack. Only the current pack's card
/// sightings are retained, then folded into per-card totals at pack boundaries.
/// This avoids retaining every pick or every draft in memory.
public final class SeventeenLandsDraftMetricsAccumulator {
    private struct PackKey: Equatable {
        let draftID: String
        let packNumber: Int
    }

    private struct PackSighting {
        var lastSeenPick: Int
        var copies: Int
    }

    private let header: SeventeenLandsCSVHeader
    private let draftIDIndex: Int
    private let packNumberIndex: Int
    private let pickNumberIndex: Int
    private let pickIndex: Int
    private let secondaryPickIndex: Int?
    private let packCardColumns: [(name: String, index: Int)]
    private var currentPack: PackKey?
    private var currentSightings: [String: PackSighting] = [:]
    private var totals: [String: SeventeenLandsDraftTotals] = [:]

    public init(header: SeventeenLandsCSVHeader) throws {
        func required(_ name: String) throws -> Int {
            guard let index = header.index(of: name) else {
                throw SeventeenLandsMetricsError.missingColumn(name)
            }
            return index
        }

        self.header = header
        self.draftIDIndex = try required("draft_id")
        self.packNumberIndex = try required("pack_number")
        self.pickNumberIndex = try required("pick_number")
        self.pickIndex = try required("pick")
        self.secondaryPickIndex = header.index(of: "pick_2")

        let columns = header.columns.enumerated().compactMap { index, column -> (String, Int)? in
            guard column.hasPrefix("pack_card_") else { return nil }
            let name = String(column.dropFirst("pack_card_".count))
            return name.isEmpty ? nil : (name, index)
        }
        guard !columns.isEmpty else {
            throw SeventeenLandsMetricsError.missingColumn("pack_card_ card columns")
        }
        self.packCardColumns = columns
    }

    public func consume(_ row: [String]) throws {
        guard row.count == header.columns.count else {
            throw SeventeenLandsCSVError.inconsistentColumnCount(
                expected: header.columns.count, actual: row.count
            )
        }

        let draftID = row[draftIDIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draftID.isEmpty else {
            throw SeventeenLandsMetricsError.invalidValue(
                column: "draft_id", value: row[draftIDIndex]
            )
        }
        let packNumber = try Self.parsePositiveInt(row[packNumberIndex], column: "pack_number")
        let pickNumber = try Self.parsePositiveInt(row[pickNumberIndex], column: "pick_number")
        let key = PackKey(draftID: draftID, packNumber: packNumber)

        if let currentPack, currentPack != key {
            finalizeCurrentPack()
        }
        currentPack = key

        for column in packCardColumns {
            let count = try Self.parseCount(row[column.index], column: header.columns[column.index])
            guard count > 0 else { continue }
            currentSightings[column.name] = PackSighting(
                lastSeenPick: pickNumber, copies: count
            )
        }

        // A picked card is known to have been present even in P1P1 rows where
        // the Arena log did not expose the rest of the pack.
        let primary = Self.nonEmptyName(row[pickIndex])
        if let primary {
            markSeen(primary, at: pickNumber)
            recordPick(primary, at: pickNumber)
        }
        if let secondaryPickIndex,
           let secondary = Self.nonEmptyName(row[secondaryPickIndex]) {
            markSeen(secondary, at: pickNumber)
            recordPick(secondary, at: pickNumber)
        }
    }

    public func finish() -> [SeventeenLandsDraftMetric] {
        finalizeCurrentPack()
        return totals.keys.sorted().compactMap { name in
            guard let value = totals[name] else { return nil }
            return SeventeenLandsDraftMetric(
                cardName: name,
                seenCount: value.seenCount,
                averageLastSeen: value.seenCount > 0
                    ? Double(value.lastSeenPickSum) / Double(value.seenCount) : nil,
                pickCount: value.pickCount,
                averageTakenAt: value.pickCount > 0
                    ? Double(value.takenAtPickSum) / Double(value.pickCount) : nil
            )
        }
    }

    private func markSeen(_ name: String, at pickNumber: Int) {
        let existing = currentSightings[name]
        currentSightings[name] = PackSighting(
            lastSeenPick: pickNumber,
            copies: max(existing?.copies ?? 0, 1)
        )
    }

    private func recordPick(_ name: String, at pickNumber: Int) {
        var value = totals[name] ?? SeventeenLandsDraftTotals()
        value.pickCount += 1
        value.takenAtPickSum += pickNumber
        totals[name] = value
    }

    private func finalizeCurrentPack() {
        for (name, sighting) in currentSightings {
            var value = totals[name] ?? SeventeenLandsDraftTotals()
            value.seenCount += sighting.copies
            value.lastSeenPickSum += sighting.lastSeenPick * sighting.copies
            totals[name] = value
        }
        currentSightings.removeAll(keepingCapacity: true)
        currentPack = nil
    }

    private static func nonEmptyName(_ value: String) -> String? {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private static func parsePositiveInt(_ value: String, column: String) throws -> Int {
        guard let number = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)),
              number > 0 else {
            throw SeventeenLandsMetricsError.invalidValue(column: column, value: value)
        }
        return number
    }

    private static func parseCount(_ value: String, column: String) throws -> Int {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        guard let count = Int(trimmed), count >= 0 else {
            throw SeventeenLandsMetricsError.invalidValue(column: column, value: value)
        }
        return count
    }
}

/// Imports draft-derived ALSA/ATA metrics into the same snapshot identity used
/// by the corresponding game archive. LocalDataStore merges the two partial
/// records so importing either archive cannot erase the other's metrics.
public enum SeventeenLandsDraftMetricsImporter {
    @discardableResult
    public static func importCSV(
        from url: URL,
        request: SeventeenLandsImportRequest,
        snapshotID: String,
        sourceUpdatedAt: Date? = nil,
        importedAt: Date = .now,
        into store: LocalDataStore
    ) throws -> DatasetSnapshot {
        guard request.userGroup == "all" else {
            throw SeventeenLandsMetricsError.unsupportedUserGroup(request.userGroup)
        }

        var accumulator: SeventeenLandsDraftMetricsAccumulator?
        let rowCount = try SeventeenLandsCSVReader.readTable(
            from: url,
            onHeader: { header in
                accumulator = try SeventeenLandsDraftMetricsAccumulator(header: header)
            },
            onRow: { row in
                try accumulator?.consume(row)
            }
        )
        let metrics = accumulator?.finish() ?? []
        guard rowCount > 0, !metrics.isEmpty else {
            throw SeventeenLandsMetricsError.missingColumn("usable draft metrics")
        }

        let snapshot = DatasetSnapshot(
            id: snapshotID,
            source: .seventeenLands,
            datasetKey: "\(request.setCode):\(request.eventType):\(request.userGroup):\(request.colorFilter ?? "all")",
            sourceUpdatedAt: sourceUpdatedAt,
            importedAt: importedAt,
            recordCount: metrics.count,
            attribution: SeventeenLandsImporter.attribution
        )

        try store.transaction {
            try store.save(snapshot: snapshot)
            for metric in metrics {
                let matches = try store.cards(named: metric.cardName, setCode: request.setCode)
                let linkedID = matches.count == 1 ? matches[0].id : nil
                try store.upsert(performance: CardPerformanceRecord(
                    snapshotID: snapshotID,
                    setCode: request.setCode,
                    eventType: request.eventType,
                    userGroup: request.userGroup,
                    colorFilter: request.colorFilter,
                    cardName: metric.cardName,
                    cardScryfallID: linkedID,
                    pickCount: metric.pickCount,
                    seenCount: metric.seenCount,
                    averageLastSeen: metric.averageLastSeen,
                    averageTakenAt: metric.averageTakenAt
                ))
            }
            return snapshot
        }
    }
}
