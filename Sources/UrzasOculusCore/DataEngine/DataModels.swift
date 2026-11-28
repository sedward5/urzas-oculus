import Foundation

public enum DatasetSource: String, Codable, Sendable {
    case scryfall
    case seventeenLands = "17lands"
}

public struct DatasetSnapshot: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let source: DatasetSource
    public let datasetKey: String
    public let sourceUpdatedAt: Date?
    public let importedAt: Date
    public let recordCount: Int
    public let attribution: String

    public init(id: String, source: DatasetSource, datasetKey: String,
                sourceUpdatedAt: Date? = nil, importedAt: Date = .now,
                recordCount: Int, attribution: String) {
        self.id = id
        self.source = source
        self.datasetKey = datasetKey
        self.sourceUpdatedAt = sourceUpdatedAt
        self.importedAt = importedAt
        self.recordCount = recordCount
        self.attribution = attribution
    }
}

/// Unweighted overall game win rate for one exact 17Lands game-archive snapshot.
/// Each source row is one game; unlike card metrics, these counts are not copy-weighted.
public struct DatasetBaselineRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let datasetKey: String
    public let snapshotID: String
    public let gameCount: Int
    public let gameWins: Int

    public var winRate: Double? {
        gameCount > 0 ? Double(gameWins) / Double(gameCount) : nil
    }

    public init(datasetKey: String, snapshotID: String, gameCount: Int, gameWins: Int) {
        self.datasetKey = datasetKey
        self.snapshotID = snapshotID
        self.gameCount = gameCount
        self.gameWins = gameWins
        self.id = "\(datasetKey)|\(snapshotID)"
    }
}

public struct CardFaceRecord: Codable, Equatable, Sendable {
    public let name: String
    public let manaCost: String?
    public let typeLine: String?
    public let oracleText: String?
    public let colors: [String]
    public let power: String?
    public let toughness: String?
    public let loyalty: String?
    public let imageURI: String?

    public init(name: String, manaCost: String? = nil, typeLine: String? = nil,
                oracleText: String? = nil, colors: [String] = [], power: String? = nil,
                toughness: String? = nil, loyalty: String? = nil, imageURI: String? = nil) {
        self.name = name
        self.manaCost = manaCost
        self.typeLine = typeLine
        self.oracleText = oracleText
        self.colors = colors
        self.power = power
        self.toughness = toughness
        self.loyalty = loyalty
        self.imageURI = imageURI
    }
}

/// One Scryfall printing. Scryfall, Oracle, and Arena identifiers are distinct.
public struct CardRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let oracleID: String?
    public let arenaID: Int?
    public let mtgoID: Int?
    public let name: String
    public let setCode: String
    public let setName: String?
    public let collectorNumber: String?
    public let rarity: String?
    public let layout: String?
    public let manaCost: String?
    public let manaValue: Double?
    public let power: String?
    public let toughness: String?
    public let typeLine: String?
    public let oracleText: String?
    public let colors: [String]
    public let colorIdentity: [String]
    public let keywords: [String]
    public let releasedAt: String?
    public let isDigital: Bool
    public let imageURI: String?
    public let cardFaces: [CardFaceRecord]

    public init(id: String, oracleID: String? = nil, arenaID: Int? = nil, mtgoID: Int? = nil,
                name: String, setCode: String, setName: String? = nil,
                collectorNumber: String? = nil, rarity: String? = nil, layout: String? = nil,
                manaCost: String? = nil, manaValue: Double? = nil, power: String? = nil,
                toughness: String? = nil, typeLine: String? = nil,
                oracleText: String? = nil, colors: [String] = [], colorIdentity: [String] = [],
                keywords: [String] = [], releasedAt: String? = nil, isDigital: Bool = false,
                imageURI: String? = nil, cardFaces: [CardFaceRecord] = []) {
        self.id = id
        self.oracleID = oracleID
        self.arenaID = arenaID
        self.mtgoID = mtgoID
        self.name = name
        self.setCode = setCode.uppercased()
        self.setName = setName
        self.collectorNumber = collectorNumber
        self.rarity = rarity
        self.layout = layout
        self.manaCost = manaCost
        self.manaValue = manaValue
        self.power = power
        self.toughness = toughness
        self.typeLine = typeLine
        self.oracleText = oracleText
        self.colors = colors
        self.colorIdentity = colorIdentity
        self.keywords = keywords
        self.releasedAt = releasedAt
        self.isDigital = isDigital
        self.imageURI = imageURI
        self.cardFaces = cardFaces
    }

    public var normalizedName: String { Self.normalizeName(name) }

    public static func normalizeName(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
    }
}

/// Rates are stored as fractions (0.57 means 57%); missing values stay nil.
public struct CardPerformanceRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let snapshotID: String
    public let setCode: String
    public let eventType: String
    public let userGroup: String
    public let colorFilter: String?
    public let cardName: String
    public let cardScryfallID: String?
    public let color: String?
    public let rarity: String?
    public let gameCount: Int?
    public let pickCount: Int?
    public let seenCount: Int?
    public let playRate: Double?
    public let winRate: Double?
    public let openingHandWinRate: Double?
    public let drawnWinRate: Double?
    public let drawnImprovementWinRate: Double?
    public let averageLastSeen: Double?
    public let averageTakenAt: Double?
    public let gamesPlayedCount: Int?
    public let gamesPlayedWinRate: Double?
    public let gamesInHandCount: Int?
    public let openingHandCount: Int?
    public let drawnCount: Int?
    public let gamesNotSeenCount: Int?
    public let gamesNotSeenWinRate: Double?
    /// Combines independently imported draft and game facets for one
    /// snapshot/card identity. Non-nil incoming values replace prior values;
    /// absent facets leave the other import intact.
    public func merging(_ newer: CardPerformanceRecord) -> CardPerformanceRecord {
        CardPerformanceRecord(
            snapshotID: snapshotID,
            setCode: setCode,
            eventType: eventType,
            userGroup: userGroup,
            colorFilter: newer.colorFilter ?? colorFilter,
            cardName: cardName,
            cardScryfallID: newer.cardScryfallID ?? cardScryfallID,
            color: newer.color ?? color,
            rarity: newer.rarity ?? rarity,
            gameCount: newer.gameCount ?? gameCount,
            pickCount: newer.pickCount ?? pickCount,
            seenCount: newer.seenCount ?? seenCount,
            playRate: newer.playRate ?? playRate,
            winRate: newer.winRate ?? winRate,
            openingHandWinRate: newer.openingHandWinRate ?? openingHandWinRate,
            drawnWinRate: newer.drawnWinRate ?? drawnWinRate,
            drawnImprovementWinRate: newer.drawnImprovementWinRate ?? drawnImprovementWinRate,
            averageLastSeen: newer.averageLastSeen ?? averageLastSeen,
            averageTakenAt: newer.averageTakenAt ?? averageTakenAt,
            gamesPlayedCount: newer.gamesPlayedCount ?? gamesPlayedCount,
            gamesPlayedWinRate: newer.gamesPlayedWinRate ?? gamesPlayedWinRate,
            gamesInHandCount: newer.gamesInHandCount ?? gamesInHandCount,
            openingHandCount: newer.openingHandCount ?? openingHandCount,
            drawnCount: newer.drawnCount ?? drawnCount,
            gamesNotSeenCount: newer.gamesNotSeenCount ?? gamesNotSeenCount,
            gamesNotSeenWinRate: newer.gamesNotSeenWinRate ?? gamesNotSeenWinRate
        )
    }


    public init(snapshotID: String, setCode: String, eventType: String,
                userGroup: String = "all", colorFilter: String? = nil,
                cardName: String, cardScryfallID: String? = nil, color: String? = nil,
                rarity: String? = nil, gameCount: Int? = nil, pickCount: Int? = nil,
                seenCount: Int? = nil,
                playRate: Double? = nil, winRate: Double? = nil,
                openingHandWinRate: Double? = nil, drawnWinRate: Double? = nil,
                drawnImprovementWinRate: Double? = nil, averageLastSeen: Double? = nil,
                averageTakenAt: Double? = nil, gamesPlayedCount: Int? = nil,
                gamesPlayedWinRate: Double? = nil, gamesInHandCount: Int? = nil,
                openingHandCount: Int? = nil, drawnCount: Int? = nil,
                gamesNotSeenCount: Int? = nil, gamesNotSeenWinRate: Double? = nil) {
        self.snapshotID = snapshotID
        self.setCode = setCode.uppercased()
        self.eventType = eventType
        self.userGroup = userGroup
        self.colorFilter = colorFilter
        self.cardName = cardName
        self.cardScryfallID = cardScryfallID
        self.color = color
        self.rarity = rarity
        self.gameCount = gameCount
        self.pickCount = pickCount
        self.seenCount = seenCount
        self.playRate = playRate
        self.winRate = winRate
        self.openingHandWinRate = openingHandWinRate
        self.drawnWinRate = drawnWinRate
        self.drawnImprovementWinRate = drawnImprovementWinRate
        self.averageLastSeen = averageLastSeen
        self.averageTakenAt = averageTakenAt
        self.gamesPlayedCount = gamesPlayedCount
        self.gamesPlayedWinRate = gamesPlayedWinRate
        self.gamesInHandCount = gamesInHandCount
        self.openingHandCount = openingHandCount
        self.drawnCount = drawnCount
        self.gamesNotSeenCount = gamesNotSeenCount
        self.gamesNotSeenWinRate = gamesNotSeenWinRate
        self.id = [snapshotID, setCode.uppercased(), eventType, userGroup,
                   colorFilter ?? "all", CardRecord.normalizeName(cardName)].joined(separator: "|")
    }
}

public enum DataEngineError: Error, Equatable {
    case sqlite(String)
    case invalidCardRecord(String)
    case invalidPerformanceRecord(String)
    case invalidDatasetBaseline(String)
    case invalidJSONLine(Int)
}
