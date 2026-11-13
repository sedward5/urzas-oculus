import Foundation

public struct ScryfallBulkManifest: Decodable, Sendable {
    public let data: [ScryfallBulkFile]
    public var defaultCards: ScryfallBulkFile? { data.first { $0.type == "default_cards" } }
    public init(data: [ScryfallBulkFile]) { self.data = data }
}

public struct ScryfallBulkFile: Decodable, Sendable {
    public let type: String
    public let updatedAt: String?
    public let downloadURI: URL?
    public let jsonlDownloadURI: URL?
    enum CodingKeys: String, CodingKey {
        case type
        case updatedAt = "updated_at"
        case downloadURI = "download_uri"
        case jsonlDownloadURI = "jsonl_download_uri"
    }
    public var preferredDownloadURL: URL? { jsonlDownloadURI }
}

public enum ScryfallImporter {
    public static let attribution = "Card data © Scryfall; https://scryfall.com"

    /// Imports the newline-delimited Scryfall default_cards export in bounded
    /// memory. Download/decompression is a separate explicit update operation.
    @discardableResult
    public static func importJSONLines(from url: URL, snapshotID: String,
                                       sourceUpdatedAt: Date? = nil,
                                       into store: LocalDataStore) throws -> DatasetSnapshot {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var pending = Data()
        var count = 0
        try store.beginTransaction()
        do {
            while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
                pending.append(chunk)
                while let newline = pending.firstIndex(of: 0x0A) {
                    let line = Data(pending[..<newline])
                    pending.removeSubrange(pending.startIndex...newline)
                    if let record = try decodeLine(line) {
                        try store.upsert(card: record)
                        count += 1
                    }
                }
            }
            if let record = try decodeLine(pending) {
                try store.upsert(card: record)
                count += 1
            }
            let snapshot = DatasetSnapshot(
                id: snapshotID, source: .scryfall, datasetKey: "default_cards",
                sourceUpdatedAt: sourceUpdatedAt, recordCount: count, attribution: attribution
            )
            try store.save(snapshot: snapshot)
            try store.commitTransaction()
            return snapshot
        } catch {
            try? store.rollbackTransaction()
            throw error
        }
    }

    private static func decodeLine(_ data: Data) throws -> CardRecord? {
        let trimmed = data.drop(while: { $0 == 0x20 || $0 == 0x09 || $0 == 0x0D })
        guard !trimmed.isEmpty else { return nil }
        return try JSONDecoder().decode(ScryfallCardDTO.self, from: Data(trimmed)).record
    }
}

private struct ScryfallCardDTO: Decodable {
    let id: String
    let oracleID: String?
    let arenaID: Int?
    let mtgoID: Int?
    let name: String
    let set: String
    let setName: String?
    let collectorNumber: String?
    let rarity: String?
    let layout: String?
    let manaCost: String?
    let manaValue: Double?
    let typeLine: String?
    let oracleText: String?
    let colors: [String]?
    let colorIdentity: [String]?
    let keywords: [String]?
    let releasedAt: String?
    let digital: Bool?
    let imageURIs: ScryfallImageURIs?
    let cardFaces: [ScryfallFaceDTO]?

    enum CodingKeys: String, CodingKey {
        case id, name, set, rarity, layout, colors, keywords, digital
        case oracleID = "oracle_id"
        case arenaID = "arena_id"
        case mtgoID = "mtgo_id"
        case setName = "set_name"
        case collectorNumber = "collector_number"
        case manaCost = "mana_cost"
        case manaValue = "cmc"
        case typeLine = "type_line"
        case oracleText = "oracle_text"
        case colorIdentity = "color_identity"
        case releasedAt = "released_at"
        case imageURIs = "image_uris"
        case cardFaces = "card_faces"
    }

    var record: CardRecord {
        CardRecord(
            id: id, oracleID: oracleID, arenaID: arenaID, mtgoID: mtgoID,
            name: name, setCode: set, setName: setName, collectorNumber: collectorNumber,
            rarity: rarity, layout: layout, manaCost: manaCost, manaValue: manaValue,
            typeLine: typeLine, oracleText: oracleText, colors: colors ?? [],
            colorIdentity: colorIdentity ?? [], keywords: keywords ?? [],
            releasedAt: releasedAt, isDigital: digital ?? false,
            imageURI: imageURIs?.normal, cardFaces: cardFaces?.map(\.record) ?? []
        )
    }
}

private struct ScryfallImageURIs: Decodable { let normal: String? }

private struct ScryfallFaceDTO: Decodable {
    let name: String
    let manaCost: String?
    let typeLine: String?
    let oracleText: String?
    let colors: [String]?
    let power: String?
    let toughness: String?
    let loyalty: String?
    let imageURIs: ScryfallImageURIs?
    enum CodingKeys: String, CodingKey {
        case name, colors, power, toughness, loyalty
        case manaCost = "mana_cost"
        case typeLine = "type_line"
        case oracleText = "oracle_text"
        case imageURIs = "image_uris"
    }
    var record: CardFaceRecord {
        CardFaceRecord(name: name, manaCost: manaCost, typeLine: typeLine,
                       oracleText: oracleText, colors: colors ?? [], power: power,
                       toughness: toughness, loyalty: loyalty, imageURI: imageURIs?.normal)
    }
}
