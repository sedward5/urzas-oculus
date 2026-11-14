import Foundation

public struct SeventeenLandsImportRequest: Equatable, Sendable {
    public let setCode: String
    public let eventType: String
    public let userGroup: String
    public let colorFilter: String?

    public init(setCode: String, eventType: String = "PremierDraft",
                userGroup: String = "all", colorFilter: String? = nil) {
        self.setCode = setCode.uppercased()
        self.eventType = eventType
        self.userGroup = userGroup
        self.colorFilter = colorFilter
    }

    /// Constructs the community-used card ratings URL. No request is made
    /// automatically; dataset updates remain explicit and outside a draft.
    public var url: URL? {
        var parts = URLComponents(string: "https://www.17lands.com/card_ratings/data")
        var query = [
            URLQueryItem(name: "expansion", value: setCode),
            URLQueryItem(name: "event_type", value: eventType),
            URLQueryItem(name: "user_group", value: userGroup)
        ]
        if let colorFilter { query.append(URLQueryItem(name: "colors", value: colorFilter)) }
        parts?.queryItems = query
        return parts?.url
    }
}

public enum SeventeenLandsImporter {
    public static let attribution = "17Lands data; https://www.17lands.com"

    /// Imports a previously acquired 17Lands card-ratings JSON snapshot.
    /// sourceUpdatedAt is the upstream dataset publication/update date, not
    /// the local download time. importedAt records when this copy was acquired.
    /// The set/format/user-group filters become part of the metric identity.
    @discardableResult
    public static func importJSON(_ data: Data, request: SeventeenLandsImportRequest,
                                  snapshotID: String, sourceUpdatedAt: Date? = nil,
                                  importedAt: Date = .now,
                                  into store: LocalDataStore) throws -> DatasetSnapshot {
        let rows = try JSONDecoder().decode([SeventeenLandsCardDTO].self, from: data)
        let snapshot = DatasetSnapshot(
            id: snapshotID, source: .seventeenLands,
            datasetKey: "\(request.setCode):\(request.eventType):\(request.userGroup):\(request.colorFilter ?? "all")",
            sourceUpdatedAt: sourceUpdatedAt, importedAt: importedAt,
            recordCount: rows.count, attribution: attribution
        )
        return try store.transaction {
            try store.save(snapshot: snapshot)
            for row in rows {
                let matches = try store.cards(named: row.name, setCode: request.setCode)
                let linkedID = matches.count == 1 ? matches[0].id : nil
                try store.upsert(performance: CardPerformanceRecord(
                    snapshotID: snapshotID, setCode: request.setCode,
                    eventType: request.eventType, userGroup: request.userGroup,
                    colorFilter: request.colorFilter, cardName: row.name,
                    cardScryfallID: linkedID, color: row.color, rarity: row.rarity,
                    gameCount: row.gameCount, pickCount: row.pickCount, playRate: row.playRate,
                    winRate: row.winRate, openingHandWinRate: row.openingHandWinRate,
                    drawnWinRate: row.drawnWinRate,
                    drawnImprovementWinRate: row.drawnImprovementWinRate,
                    averageLastSeen: row.averageLastSeen, averageTakenAt: row.averageTakenAt
                ))
            }
            return snapshot
        }
    }
}

private struct SeventeenLandsCardDTO: Decodable {
    let name: String
    let color: String?
    let rarity: String?
    let gameCount: Int?
    let pickCount: Int?
    let playRate: Double?
    let winRate: Double?
    let openingHandWinRate: Double?
    let drawnWinRate: Double?
    let drawnImprovementWinRate: Double?
    let averageLastSeen: Double?
    let averageTakenAt: Double?

    enum CodingKeys: String, CodingKey {
        case name, color, rarity
        case gameCount = "game_count"
        case pickCount = "pick_count"
        case playRate = "play_rate"
        case winRate = "win_rate"
        case openingHandWinRate = "opening_hand_win_rate"
        case drawnWinRate = "drawn_win_rate"
        case drawnImprovementWinRate = "drawn_improvement_win_rate"
        case averageLastSeen = "avg_seen"
        case averageTakenAt = "avg_pick"
    }
}
