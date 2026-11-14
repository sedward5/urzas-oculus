import Foundation

public enum SeventeenLandsMetricsError: Error, Equatable {
    case missingColumn(String)
    case invalidValue(column: String, value: String)
    case unsupportedUserGroup(String)
}

/// Weighted game-level statistics for one card. Copy counts, including
/// gameCount, follow 17Lands' per-copy weighting.
public struct SeventeenLandsGameMetric: Equatable, Sendable {
    public let cardName: String
    public let gameCount: Int
    public let gamesPlayedCount: Int
    public let gamesPlayedWinRate: Double?
    public let playRate: Double?
    public let gamesInHandCount: Int
    public let gamesInHandWinRate: Double?
    public let openingHandCount: Int
    public let openingHandWinRate: Double?
    public let drawnCount: Int
    public let drawnWinRate: Double?
    public let gamesNotSeenCount: Int
    public let gamesNotSeenWinRate: Double?
    public let improvementInHand: Double?
}

private struct SeventeenLandsGameTotals {
    var gamesPlayed = 0
    var gamesPlayedWins = 0
    var maindeckCopies = 0
    var sideboardCopies = 0
    var gamesInHand = 0
    var gamesInHandWins = 0
    var openingHand = 0
    var openingHandWins = 0
    var drawn = 0
    var drawnWins = 0
    var notSeen = 0
    var notSeenWins = 0
}

/// Aggregates the wide, set-specific game CSV one row at a time.
/// Card columns are discovered by their documented facet prefixes, never by
/// hard-coded positions. Memory use is bounded by the number of cards in a set.
public final class SeventeenLandsGameMetricsAccumulator {
    private static let facets = [
        "opening_hand_", "drawn_", "tutored_", "deck_", "sideboard_"
    ]

    private let header: SeventeenLandsCSVHeader
    private let wonIndex: Int
    private let mainColorsIndex: Int?
    private let colorFilter: String?
    private let cardColumns: [(name: String, facet: String, index: Int)]
    private var totals: [String: SeventeenLandsGameTotals] = [:]

    public init(header: SeventeenLandsCSVHeader, colorFilter: String? = nil) throws {
        guard let wonIndex = header.index(of: "won") else {
            throw SeventeenLandsMetricsError.missingColumn("won")
        }
        self.header = header
        self.wonIndex = wonIndex
        self.mainColorsIndex = header.index(of: "main_colors")
        self.colorFilter = colorFilter?.uppercased()
        if colorFilter != nil, mainColorsIndex == nil {
            throw SeventeenLandsMetricsError.missingColumn("main_colors")
        }

        var columns: [(name: String, facet: String, index: Int)] = []
        for (index, column) in header.columns.enumerated() {
            guard let facet = Self.facets.first(where: { column.hasPrefix($0) }) else {
                continue
            }
            let name = String(column.dropFirst(facet.count))
            guard !name.isEmpty else { continue }
            columns.append((name, facet, index))
        }
        guard !columns.isEmpty else {
            throw SeventeenLandsMetricsError.missingColumn("card facet columns")
        }
        self.cardColumns = columns
    }

    public func consume(_ row: [String]) throws {
        guard row.count == header.columns.count, row.indices.contains(wonIndex) else {
            throw SeventeenLandsCSVError.inconsistentColumnCount(
                expected: header.columns.count, actual: row.count
            )
        }
        if let colorFilter, let mainColorsIndex,
           row[mainColorsIndex].uppercased() != colorFilter {
            return
        }

        let won = try Self.parseBoolean(row[wonIndex], column: "won")
        var observations: [String: CardObservation] = [:]
        for column in cardColumns {
            let count = try Self.parseCount(row[column.index], column: header.columns[column.index])
            guard count > 0 else { continue }
            var observation = observations[column.name] ?? CardObservation()
            switch column.facet {
            case "opening_hand_": observation.openingHand = count
            case "drawn_": observation.drawn = count
            case "tutored_": observation.tutored = count
            case "deck_": observation.deck = count
            case "sideboard_": observation.sideboard = count
            default: break
            }
            observations[column.name] = observation
        }

        for (name, observation) in observations {
            var value = totals[name] ?? SeventeenLandsGameTotals()
            if observation.deck > 0 {
                value.gamesPlayed += observation.deck
                if won { value.gamesPlayedWins += observation.deck }
            }
            value.maindeckCopies += observation.deck
            value.sideboardCopies += observation.sideboard

            let inHand = observation.openingHand + observation.drawn
            value.gamesInHand += inHand
            if won { value.gamesInHandWins += inHand }
            value.openingHand += observation.openingHand
            if won { value.openingHandWins += observation.openingHand }
            value.drawn += observation.drawn
            if won { value.drawnWins += observation.drawn }

            let unseen = max(0, observation.deck -
                observation.openingHand - observation.drawn - observation.tutored)
            value.notSeen += unseen
            if won { value.notSeenWins += unseen }
            totals[name] = value
        }
    }

    public func finish() -> [SeventeenLandsGameMetric] {
        totals.keys.sorted().compactMap { name in
            guard let value = totals[name] else { return nil }
            let gih = Self.rate(wins: value.gamesInHandWins, count: value.gamesInHand)
            let gns = Self.rate(wins: value.notSeenWins, count: value.notSeen)
            return SeventeenLandsGameMetric(
                cardName: name,
                gameCount: value.gamesPlayed,
                gamesPlayedCount: value.gamesPlayed,
                gamesPlayedWinRate: Self.rate(wins: value.gamesPlayedWins, count: value.gamesPlayed),
                playRate: Self.rate(
                    wins: value.maindeckCopies,
                    count: value.maindeckCopies + value.sideboardCopies
                ),
                gamesInHandCount: value.gamesInHand,
                gamesInHandWinRate: gih,
                openingHandCount: value.openingHand,
                openingHandWinRate: Self.rate(wins: value.openingHandWins, count: value.openingHand),
                drawnCount: value.drawn,
                drawnWinRate: Self.rate(wins: value.drawnWins, count: value.drawn),
                gamesNotSeenCount: value.notSeen,
                gamesNotSeenWinRate: gns,
                improvementInHand: gih.flatMap { hand in gns.map { hand - $0 } }
            )
        }
    }

    private struct CardObservation {
        var openingHand = 0
        var drawn = 0
        var tutored = 0
        var deck = 0
        var sideboard = 0
    }

    private static func rate(wins: Int, count: Int) -> Double? {
        count > 0 ? Double(wins) / Double(count) : nil
    }

    private static func parseCount(_ value: String, column: String) throws -> Int {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        guard let count = Int(trimmed), count >= 0 else {
            throw SeventeenLandsMetricsError.invalidValue(column: column, value: value)
        }
        return count
    }

    private static func parseBoolean(_ value: String, column: String) throws -> Bool {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "1": return true
        case "false", "0": return false
        default: throw SeventeenLandsMetricsError.invalidValue(column: column, value: value)
        }
    }
}

/// Imports and aggregates one official 17Lands game archive into the local
/// reference store. Draft statistics (ALSA/ATA) are supplied by the separate
/// draft archive pipeline and remain nil until that archive is imported.
public enum SeventeenLandsGameMetricsImporter {
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

        var accumulator: SeventeenLandsGameMetricsAccumulator?
        let rowCount = try SeventeenLandsCSVReader.readTable(
            from: url,
            onHeader: { header in
                accumulator = try SeventeenLandsGameMetricsAccumulator(
                    header: header, colorFilter: request.colorFilter
                )
            },
            onRow: { row in
                try accumulator?.consume(row)
            }
        )
        guard rowCount > 0, let metrics = accumulator?.finish(), !metrics.isEmpty else {
            throw SeventeenLandsMetricsError.missingColumn("usable card metrics")
        }

        let snapshot = DatasetSnapshot(
            id: snapshotID,
            source: .seventeenLands,
            datasetKey: "\(request.setCode):\(request.eventType):\(request.userGroup):\(request.colorFilter ?? "all)",
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
                    gameCount: metric.gameCount,
                    playRate: metric.playRate,
                    winRate: metric.gamesInHandWinRate,
                    openingHandWinRate: metric.openingHandWinRate,
                    drawnWinRate: metric.drawnWinRate,
                    drawnImprovementWinRate: metric.improvementInHand,
                    gamesPlayedCount: metric.gamesPlayedCount,
                    gamesPlayedWinRate: metric.gamesPlayedWinRate,
                    gamesInHandCount: metric.gamesInHandCount,
                    openingHandCount: metric.openingHandCount,
                    drawnCount: metric.drawnCount,
                    gamesNotSeenCount: metric.gamesNotSeenCount,
                    gamesNotSeenWinRate: metric.gamesNotSeenWinRate
                ))
            }
        }
        return snapshot
    }
}
