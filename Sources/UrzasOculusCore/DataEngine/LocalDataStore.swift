import Foundation
import CSQLite

public final class LocalDataStore: @unchecked Sendable {
    private var database: OpaquePointer?
    private let lock = NSRecursiveLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(url: URL) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database"
            if let handle { sqlite3_close(handle) }
            throw DataEngineError.sqlite(message)
        }
        database = handle
        sqlite3_busy_timeout(handle, 5_000)
        try execute("PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL;")
        try createSchema()
    }

    deinit { if let database { sqlite3_close(database) } }

    public func beginTransaction() throws { try execute("BEGIN IMMEDIATE") }
    public func commitTransaction() throws { try execute("COMMIT") }
    public func rollbackTransaction() throws { try execute("ROLLBACK") }

    /// Holds the connection lock for the full transaction so another caller
    /// cannot accidentally interleave writes into an import.
    public func transaction<T>(_ operation: () throws -> T) throws -> T {
        try withLock {
            try execute("BEGIN IMMEDIATE")
            do {
                let result = try operation()
                try execute("COMMIT")
                return result
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    /// Records successful import provenance for one independently acquired dataset facet.
    public func save(component: DatasetComponentSnapshot) throws {
        try withStatement("""
        INSERT INTO dataset_components
          (id, dataset_key, kind, snapshot_id, source_updated_at, imported_at, record_count)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET snapshot_id=excluded.snapshot_id,
          source_updated_at=excluded.source_updated_at, imported_at=excluded.imported_at,
          record_count=excluded.record_count
        """) { s in
            bind(component.id, 1, s); bind(component.datasetKey, 2, s)
            bind(component.kind.rawValue, 3, s); bind(component.snapshotID, 4, s)
            bind(component.sourceUpdatedAt?.timeIntervalSince1970, 5, s)
            bind(component.importedAt.timeIntervalSince1970, 6, s)
            bind(component.recordCount, 7, s); try stepDone(s)
        }
    }

    public func components(datasetKey: String) throws -> [DatasetComponentSnapshot] {
        try withStatement("""
        SELECT dataset_key, kind, snapshot_id, source_updated_at, imported_at, record_count
        FROM dataset_components WHERE dataset_key = ?
        """) { s in
            bind(datasetKey, 1, s)
            var result: [DatasetComponentSnapshot] = []
            while sqlite3_step(s) == SQLITE_ROW {
                guard let key = columnText(s, 0),
                      let rawKind = columnText(s, 1),
                      let kind = DatasetComponentKind(rawValue: rawKind),
                      let snapshotID = columnText(s, 2) else { continue }
                let sourceTime = sqlite3_column_type(s, 3) == SQLITE_NULL
                    ? nil : Date(timeIntervalSince1970: sqlite3_column_double(s, 3))
                let importedAt = Date(timeIntervalSince1970: sqlite3_column_double(s, 4))
                result.append(DatasetComponentSnapshot(
                    datasetKey: key, kind: kind, snapshotID: snapshotID,
                    sourceUpdatedAt: sourceTime, importedAt: importedAt,
                    recordCount: Int(sqlite3_column_int64(s, 5))
                ))
            }
            return result
        }
    }

    public func save(snapshot: DatasetSnapshot) throws {
        try withStatement("""
        INSERT INTO dataset_snapshots
          (id, source, dataset_key, source_updated_at, imported_at, record_count, attribution)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET source=excluded.source, dataset_key=excluded.dataset_key,
          source_updated_at=excluded.source_updated_at, imported_at=excluded.imported_at,
          record_count=excluded.record_count, attribution=excluded.attribution
        """) { s in
            bind(snapshot.id, 1, s); bind(snapshot.source.rawValue, 2, s)
            bind(snapshot.datasetKey, 3, s); bind(snapshot.sourceUpdatedAt?.timeIntervalSince1970, 4, s)
            bind(snapshot.importedAt.timeIntervalSince1970, 5, s); bind(snapshot.recordCount, 6, s)
            bind(snapshot.attribution, 7, s); try stepDone(s)
        }
    }

    /// Persists the overall, unweighted game baseline for one source snapshot.
    public func save(baseline: DatasetBaselineRecord) throws {
        guard baseline.gameCount > 0, baseline.gameWins >= 0,
              baseline.gameWins <= baseline.gameCount else {
            throw DataEngineError.invalidDatasetBaseline(baseline.datasetKey)
        }
        let snapshotMatches = try withStatement(
            "SELECT 1 FROM dataset_snapshots WHERE id = ? AND dataset_key = ?"
        ) { s in
            bind(baseline.snapshotID, 1, s)
            bind(baseline.datasetKey, 2, s)
            return sqlite3_step(s) == SQLITE_ROW
        }
        guard snapshotMatches else {
            throw DataEngineError.invalidDatasetBaseline(baseline.datasetKey)
        }
        let payload = try encoder.encode(baseline)
        try withStatement("""
        INSERT INTO dataset_baselines
          (id, dataset_key, snapshot_id, game_count, game_wins, payload)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET game_count=excluded.game_count,
          game_wins=excluded.game_wins, payload=excluded.payload
        """) { s in
            bind(baseline.id, 1, s)
            bind(baseline.datasetKey, 2, s)
            bind(baseline.snapshotID, 3, s)
            bind(baseline.gameCount, 4, s)
            bind(baseline.gameWins, 5, s)
            bind(payload, 6, s)
            try stepDone(s)
        }
    }

    /// Retrieves a baseline only for the exact dataset key and snapshot identity.
    public func baseline(datasetKey: String, snapshotID: String) throws -> DatasetBaselineRecord? {
        try queryOne(
            "SELECT payload FROM dataset_baselines WHERE id = ?",
            value: "\(datasetKey)|\(snapshotID)"
        )
    }

    public func upsert(card: CardRecord) throws {
        guard !card.id.isEmpty, !card.name.isEmpty, !card.setCode.isEmpty else {
            throw DataEngineError.invalidCardRecord(card.id)
        }
        let payload = try encoder.encode(card)
        try withStatement("""
        INSERT INTO cards
          (scryfall_id, oracle_id, arena_id, mtgo_id, name, normalized_name, set_code,
           mana_value, type_line, rarity, payload)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(scryfall_id) DO UPDATE SET oracle_id=excluded.oracle_id,
          arena_id=excluded.arena_id, mtgo_id=excluded.mtgo_id, name=excluded.name,
          normalized_name=excluded.normalized_name, set_code=excluded.set_code,
          mana_value=excluded.mana_value, type_line=excluded.type_line,
          rarity=excluded.rarity, payload=excluded.payload
        """) { s in
            bind(card.id, 1, s); bind(card.oracleID, 2, s); bind(card.arenaID, 3, s)
            bind(card.mtgoID, 4, s); bind(card.name, 5, s); bind(card.normalizedName, 6, s)
            bind(card.setCode, 7, s); bind(card.manaValue, 8, s); bind(card.typeLine, 9, s)
            bind(card.rarity, 10, s); bind(payload, 11, s); try stepDone(s)
        }
    }

    public func upsert(performance: CardPerformanceRecord) throws {
        guard !performance.cardName.isEmpty, !performance.setCode.isEmpty else {
            throw DataEngineError.invalidPerformanceRecord(performance.cardName)
        }
        let existing: CardPerformanceRecord? = try queryOne(
            "SELECT payload FROM card_performance WHERE id = ?", value: performance.id
        )
        let merged = existing?.merging(performance) ?? performance
        let payload = try encoder.encode(merged)
        try withStatement("""
        INSERT INTO card_performance
          (id, snapshot_id, scryfall_id, set_code, event_type, user_group, color_filter,
           normalized_name, game_count, win_rate, average_last_seen, average_taken_at, payload)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET snapshot_id=excluded.snapshot_id,
          scryfall_id=excluded.scryfall_id, game_count=excluded.game_count,
          win_rate=excluded.win_rate, average_last_seen=excluded.average_last_seen,
          average_taken_at=excluded.average_taken_at, payload=excluded.payload
        """) { statement in
            bind(merged.id, 1, statement); bind(merged.snapshotID, 2, statement)
            bind(merged.cardScryfallID, 3, statement); bind(merged.setCode, 4, statement)
            bind(merged.eventType, 5, statement); bind(merged.userGroup, 6, statement)
            bind(merged.colorFilter ?? "all", 7, statement)
            bind(CardRecord.normalizeName(merged.cardName), 8, statement)
            bind(merged.gameCount, 9, statement); bind(merged.winRate, 10, statement)
            bind(merged.averageLastSeen, 11, statement); bind(merged.averageTakenAt, 12, statement)
            bind(payload, 13, statement); try stepDone(statement)
        }
    }

    public func card(scryfallID: String) throws -> CardRecord? {
        try queryOne("SELECT payload FROM cards WHERE scryfall_id = ?", value: scryfallID)
    }

    /// Returns every printing that shares an Arena identifier.
    public func cards(arenaID: Int) throws -> [CardRecord] {
        try withStatement("SELECT payload FROM cards WHERE arena_id = ? ORDER BY set_code") { s in
            bind(arenaID, 1, s)
            var result: [CardRecord] = []
            while sqlite3_step(s) == SQLITE_ROW {
                if let data = columnData(s, 0) {
                    result.append(try decoder.decode(CardRecord.self, from: data))
                }
            }
            return result
        }
    }

    /// Returns a result only when the Arena identifier is unambiguous.
    /// Supply a set code when the same Arena ID appears on multiple printings.
    public func card(arenaID: Int, setCode: String? = nil) throws -> CardRecord? {
        let matches = try cards(arenaID: arenaID).filter {
            setCode == nil || $0.setCode == setCode?.uppercased()
        }
        return matches.count == 1 ? matches[0] : nil
    }

    public func cards(named name: String, setCode: String? = nil) throws -> [CardRecord] {
        try withStatement(setCode == nil
            ? "SELECT payload FROM cards WHERE normalized_name = ? ORDER BY set_code"
            : "SELECT payload FROM cards WHERE normalized_name = ? AND set_code = ? ORDER BY set_code") { s in
            bind(CardRecord.normalizeName(name), 1, s)
            if let setCode { bind(setCode.uppercased(), 2, s) }
            var result: [CardRecord] = []
            while sqlite3_step(s) == SQLITE_ROW {
                if let data = columnData(s, 0) { result.append(try decoder.decode(CardRecord.self, from: data)) }
            }
            return result
        }
    }

    public func performance(setCode: String, eventType: String, cardName: String,
                            userGroup: String = "all", colorFilter: String? = nil) throws -> CardPerformanceRecord? {
        try withStatement("""
        SELECT payload FROM card_performance
        WHERE set_code=? AND event_type=? AND user_group=? AND color_filter=? AND normalized_name=?
        ORDER BY rowid DESC LIMIT 1
        """) { s in
            bind(setCode.uppercased(), 1, s); bind(eventType, 2, s); bind(userGroup, 3, s)
            bind(colorFilter ?? "all", 4, s); bind(CardRecord.normalizeName(cardName), 5, s)
            guard sqlite3_step(s) == SQLITE_ROW, let data = columnData(s, 0) else { return nil }
            return try decoder.decode(CardPerformanceRecord.self, from: data)
        }
    }

    public func cardCount() throws -> Int { try scalarInt("SELECT COUNT(*) FROM cards") }
    public func performanceCount() throws -> Int { try scalarInt("SELECT COUNT(*) FROM card_performance") }

    public func close() throws {
        try withLock {
            guard let database else { return }
            guard sqlite3_close(database) == SQLITE_OK else { throw makeError() }
            self.database = nil
        }
    }

    private func createSchema() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS dataset_snapshots (
          id TEXT PRIMARY KEY, source TEXT NOT NULL, dataset_key TEXT NOT NULL,
          source_updated_at REAL, imported_at REAL NOT NULL, record_count INTEGER NOT NULL,
          attribution TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_snapshots_source_key
          ON dataset_snapshots(source, dataset_key, imported_at DESC);
        CREATE TABLE IF NOT EXISTS dataset_baselines (
          id TEXT PRIMARY KEY, dataset_key TEXT NOT NULL, snapshot_id TEXT NOT NULL,
          game_count INTEGER NOT NULL, game_wins INTEGER NOT NULL, payload BLOB NOT NULL,
          FOREIGN KEY(snapshot_id) REFERENCES dataset_snapshots(id)
        );
        CREATE INDEX IF NOT EXISTS idx_dataset_baselines_scope
          ON dataset_baselines(dataset_key, snapshot_id);
        CREATE TABLE IF NOT EXISTS dataset_components (
          id TEXT PRIMARY KEY, dataset_key TEXT NOT NULL, kind TEXT NOT NULL,
          snapshot_id TEXT NOT NULL, source_updated_at REAL, imported_at REAL NOT NULL,
          record_count INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_dataset_components_key
          ON dataset_components(dataset_key, kind);
        CREATE TABLE IF NOT EXISTS cards (
          scryfall_id TEXT PRIMARY KEY, oracle_id TEXT, arena_id INTEGER, mtgo_id INTEGER,
          name TEXT NOT NULL, normalized_name TEXT NOT NULL, set_code TEXT NOT NULL,
          mana_value REAL, type_line TEXT, rarity TEXT, payload BLOB NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_cards_arena ON cards(arena_id);
        CREATE INDEX IF NOT EXISTS idx_cards_oracle ON cards(oracle_id);
        CREATE INDEX IF NOT EXISTS idx_cards_name_set ON cards(normalized_name, set_code);
        CREATE TABLE IF NOT EXISTS card_performance (
          id TEXT PRIMARY KEY, snapshot_id TEXT NOT NULL, scryfall_id TEXT,
          set_code TEXT NOT NULL, event_type TEXT NOT NULL, user_group TEXT NOT NULL,
          color_filter TEXT NOT NULL, normalized_name TEXT NOT NULL, game_count INTEGER,
          win_rate REAL, average_last_seen REAL, average_taken_at REAL, payload BLOB NOT NULL,
          FOREIGN KEY(snapshot_id) REFERENCES dataset_snapshots(id),
          FOREIGN KEY(scryfall_id) REFERENCES cards(scryfall_id)
        );
        CREATE INDEX IF NOT EXISTS idx_performance_lookup
          ON card_performance(set_code, event_type, user_group, color_filter, normalized_name);
        """)
    }

    private func execute(_ sql: String) throws {
        try withLock {
            var error: UnsafeMutablePointer<CChar>?
            let result = sqlite3_exec(database, sql, nil, nil, &error)
            guard result == SQLITE_OK else {
                let message = error.map { String(cString: $0) } ?? makeError().localizedDescription
                sqlite3_free(error)
                throw DataEngineError.sqlite(message)
            }
        }
    }

    private func withStatement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        try withLock {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
                  let statement else { throw makeError() }
            defer { sqlite3_finalize(statement) }
            return try body(statement)
        }
    }

    private func queryOne<T: Decodable>(_ sql: String, value: String) throws -> T? {
        try withStatement(sql) { s in
            bind(value, 1, s)
            guard sqlite3_step(s) == SQLITE_ROW, let data = columnData(s, 0) else { return nil }
            return try decoder.decode(T.self, from: data)
        }
    }

    private func scalarInt(_ sql: String) throws -> Int {
        try withStatement(sql) { s in
            guard sqlite3_step(s) == SQLITE_ROW else { throw makeError() }
            return Int(sqlite3_column_int64(s, 0))
        }
    }

    private func columnText(_ s: OpaquePointer, _ index: Int32) -> String? {
        guard let value = sqlite3_column_text(s, index) else { return nil }
        return String(cString: value)
    }

    private func columnData(_ s: OpaquePointer, _ index: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(s, index) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(s, index)))
    }

    private func stepDone(_ s: OpaquePointer) throws {
        guard sqlite3_step(s) == SQLITE_DONE else { throw makeError() }
    }

    private func bind(_ value: String?, _ index: Int32, _ s: OpaquePointer) {
        guard let value else { sqlite3_bind_null(s, index); return }
        sqlite3_bind_text(s, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }
    private func bind(_ value: Int?, _ index: Int32, _ s: OpaquePointer) {
        guard let value else { sqlite3_bind_null(s, index); return }
        sqlite3_bind_int64(s, index, sqlite3_int64(value))
    }
    private func bind(_ value: Double?, _ index: Int32, _ s: OpaquePointer) {
        guard let value else { sqlite3_bind_null(s, index); return }
        sqlite3_bind_double(s, index, value)
    }
    private func bind(_ value: Data, _ index: Int32, _ s: OpaquePointer) {
        value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(s, index, bytes.baseAddress, Int32(bytes.count),
                              unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
    }
    private func makeError() -> DataEngineError {
        .sqlite(database.map { String(cString: sqlite3_errmsg($0)) } ?? "Database is closed")
    }
    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }; return try body()
    }
}
