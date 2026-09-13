import Foundation

#if canImport(SQLiteShim)
import SQLiteShim
#endif

enum DatabaseError: Error, LocalizedError {
    case unavailable
    case prepare(String)
    case bind(String)
    case execute(String)
    case invalidDatabasePath
    case indexedLocationOverlaps(existing: String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "The search database is not available."
        case .prepare(let message):
            return "Unable to prepare database query: \(message)"
        case .bind(let message):
            return "Unable to bind database value: \(message)"
        case .execute(let message):
            return "Unable to execute database query: \(message)"
        case .invalidDatabasePath:
            return "The search database path is invalid."
        case .indexedLocationOverlaps(let existing):
            return "The selected folder overlaps the indexed location \(existing)."
        }
    }
}

actor FileDatabase {
    private static let currentSchemaVersion: Int64 = 2
    private static let currentFTSVersion = "2"

    private struct FTSSetup {
        let available: Bool
        let needsRebuild: Bool
    }

    private enum SQLiteValue {
        case text(String)
        case integer(Int32)
        case int64(Int64)
        case double(Double)
    }

    private let databaseURL: URL
    private let readOnly: Bool
    private var connection: OpaquePointer?
    private(set) var isReady = false
    private(set) var ftsAvailable = false
    private var ftsNeedsRebuild = false
    private(set) var regexpAvailable = false
    private(set) var isWritable = false
    private(set) var startupError: String?

    private var isInMemory: Bool {
        databaseURL.path == ":memory:" || databaseURL.lastPathComponent == ":memory:"
    }

    private var sqlitePath: String {
        isInMemory ? ":memory:" : databaseURL.path
    }

    init(databaseURL: URL, readOnly: Bool = false) {
        self.databaseURL = databaseURL
        self.readOnly = readOnly

        do {
            let inMemory = databaseURL.path == ":memory:" || databaseURL.lastPathComponent == ":memory:"
            let sqlitePath = inMemory ? ":memory:" : databaseURL.path

            if !inMemory && !readOnly {
                try FileManager.default.createDirectory(
                    at: databaseURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
            }

            var openedConnection: OpaquePointer?
            let openFlags = (readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE)
                | SQLITE_OPEN_FULLMUTEX
            let result = sqlitePath.withCString { path in
                sqlite3_open_v2(
                    path,
                    &openedConnection,
                    openFlags,
                    nil
                )
            }

            guard result == SQLITE_OK, let openedConnection else {
                let message = openedConnection.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
                AppLogger.database.error("SQLite open failed: \(message, privacy: .public)")
                if let openedConnection {
                    sqlite3_close_v2(openedConnection)
                }
                self.connection = nil
                self.startupError = "SQLite open failed: \(message)"
                return
            }

            self.connection = openedConnection
            do {
                sqlite3_busy_timeout(openedConnection, 2_500)
                let regexpResult = nfs_sqlite_register_regexp(openedConnection)
                guard regexpResult == SQLITE_OK else {
                    throw DatabaseError.execute("Unable to register SQLite regexp function: \(regexpResult)")
                }
                self.regexpAvailable = true
                if readOnly {
                    guard Self.hasSearchSchema(connection: openedConnection) else {
                        throw DatabaseError.execute("Search schema is not available")
                    }
                    self.ftsAvailable = Self.readOnlyFTSAvailable(connection: openedConnection)
                } else {
                    let setup = try Self.configure(connection: openedConnection)
                    self.ftsAvailable = setup.available && !setup.needsRebuild
                    self.ftsNeedsRebuild = setup.needsRebuild
                }
                self.isReady = true
                self.isWritable = !readOnly
            } catch {
                let configurationError = String(describing: error)
                if !readOnly && Self.hasSearchSchema(connection: openedConnection) {
                    // Existing indexes remain useful when the app can read the
                    // database but cannot update WAL/schema metadata.
                    AppLogger.database.warning("SQLite opened read-only; indexing updates are disabled: \(configurationError, privacy: .public)")
                    self.ftsAvailable = false
                    self.isReady = true
                    self.isWritable = false
                    self.startupError = "Database opened read-only: \(configurationError)"
                } else {
                    AppLogger.database.error("SQLite schema setup failed: \(configurationError, privacy: .public)")
                    sqlite3_close_v2(openedConnection)
                    self.connection = nil
                    self.startupError = configurationError
                }
            }
        } catch {
            AppLogger.database.error("Cannot create database directory: \(String(describing: error), privacy: .public)")
            self.connection = nil
            self.startupError = String(describing: error)
        }
    }

    deinit {
        if let connection {
            sqlite3_close_v2(connection)
        }
    }

    func indexedLocations() -> [IndexedLocation] {
        do {
            let statement = try prepare(
                "SELECT path, is_paused, is_offline, last_scan_at, file_count FROM indexed_locations ORDER BY path COLLATE NOCASE"
            )
            defer { sqlite3_finalize(statement) }

            var locations: [IndexedLocation] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let path = textColumn(statement, 0)
                let paused = sqlite3_column_int(statement, 1) != 0
                let offline = sqlite3_column_int(statement, 2) != 0
                let lastScan = sqlite3_column_type(statement, 3) == SQLITE_NULL
                    ? nil
                    : Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
                let fileCount = Int(sqlite3_column_int64(statement, 4))
                locations.append(
                    IndexedLocation(
                        path: path,
                        isPaused: paused,
                        isOffline: offline,
                        lastScanDate: lastScan,
                        fileCount: fileCount
                    )
                )
            }
            return locations
        } catch {
            AppLogger.database.error("Cannot load indexed locations: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    func addIndexedLocation(path: String) throws {
        try requireReady()
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let existingLocations = try indexedLocationPaths()
        if let overlappingLocation = existingLocations.first(where: { existingPath in
            existingPath != normalizedPath
                && (isPath(normalizedPath, inside: existingPath)
                    || isPath(existingPath, inside: normalizedPath))
        }) {
            throw DatabaseError.indexedLocationOverlaps(existing: overlappingLocation)
        }

        let statement = try prepare(
            """
            INSERT INTO indexed_locations(path, is_paused, last_scan_at, file_count)
            VALUES (?, 0, NULL, 0)
            ON CONFLICT(path) DO NOTHING
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind([.text(normalizedPath)], to: statement)
        try stepToDone(statement)
    }

    func setLocationPaused(path: String, isPaused: Bool) throws {
        try requireReady()
        try execute(
            "UPDATE indexed_locations SET is_paused = ? WHERE path = ?",
            bindings: [.integer(isPaused ? 1 : 0), .text(path)]
        )
    }

    func setLocationOffline(path: String, isOffline: Bool) throws {
        try requireReady()
        try execute(
            "UPDATE indexed_locations SET is_offline = ? WHERE path = ?",
            bindings: [.integer(isOffline ? 1 : 0), .text(path)]
        )
    }

    func removeIndexedLocation(path: String) throws {
        try requireReady()
        try transaction {
            try deleteSubtree(path: path)
            try execute("DELETE FROM indexed_locations WHERE path = ?", bindings: [.text(path)])
        }
    }

    func beginGeneration() throws -> Int64 {
        try requireReady()
        let statement = try prepare("SELECT COALESCE(MAX(last_seen_generation), 0) + 1 FROM files")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw DatabaseError.execute(lastErrorMessage)
        }
        return sqlite3_column_int64(statement, 0)
    }

    func upsert(_ records: [FileMetadata], generation: Int64) throws {
        guard !records.isEmpty else { return }
        try requireReady()

        let sql =
            """
            INSERT INTO files(
                filename, full_path, extension, is_directory, file_size,
                modification_date, parent_path, normalized_filename,
                normalized_path, root_path, last_seen_generation
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(full_path) DO UPDATE SET
                filename = excluded.filename,
                extension = excluded.extension,
                is_directory = excluded.is_directory,
                file_size = excluded.file_size,
                modification_date = excluded.modification_date,
                parent_path = excluded.parent_path,
                normalized_filename = excluded.normalized_filename,
                normalized_path = excluded.normalized_path,
                root_path = excluded.root_path,
                last_seen_generation = excluded.last_seen_generation
            """

        try transaction {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }

            for record in records {
                try bind(
                    [
                        .text(record.filename),
                        .text(record.fullPath),
                        .text(record.fileExtension),
                        .integer(record.isDirectory ? 1 : 0),
                        .int64(record.fileSize),
                        .double(record.modificationDate.timeIntervalSince1970),
                        .text(record.parentPath),
                        .text(record.normalizedFilename),
                        .text(record.normalizedPath),
                        .text(record.rootPath),
                        .int64(generation)
                    ],
                    to: statement
                )
                try stepToDone(statement)
                sqlite3_reset(statement)
            }
        }
    }

    func deletePath(_ path: String) throws {
        try requireReady()
        try deleteSubtree(path: path)
    }

    func removeUnseen(path: String, rootPath: String, generation: Int64) throws {
        try requireReady()
        let sql: String
        var bindings: [SQLiteValue]

        if path == "/" {
            sql = "DELETE FROM files WHERE root_path = ? AND last_seen_generation < ?"
            bindings = [.text(rootPath), .int64(generation)]
        } else {
            sql =
                """
                DELETE FROM files
                WHERE root_path = ?
                  AND last_seen_generation < ?
                  AND (
                      full_path = ?
                      OR substr(full_path, 1, length(?) + 1) = ? || '/'
                  )
                """
            bindings = [
                .text(rootPath),
                .int64(generation),
                .text(path),
                .text(path),
                .text(path)
            ]
        }

        try execute(sql, bindings: bindings)
    }

    func finishScan(rootPath: String, scanDate: Date) throws {
        try requireReady()
        let statement = try prepare(
            """
            UPDATE indexed_locations
            SET last_scan_at = ?,
                is_offline = 0,
                file_count = (
                    SELECT COUNT(*) FROM files
                    WHERE root_path = ? AND is_directory = 0
                )
            WHERE path = ?
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(
            [
                .double(scanDate.timeIntervalSince1970),
                .text(rootPath),
                .text(rootPath)
            ],
            to: statement
        )
        try stepToDone(statement)
    }

    func markUsed(path: String, date: Date = Date()) throws {
        try requireReady()
        try execute(
            "UPDATE files SET last_used_at = ? WHERE full_path = ?",
            bindings: [.double(date.timeIntervalSince1970), .text(path)]
        )
    }

    /// Rebuilds the external-content FTS index away from the main actor. The
    /// regular search path remains available through instr() while this work
    /// is in progress, so a large existing database never blocks the UI and
    /// never exposes a half-built FTS index.
    func prepareSearchAcceleration() {
        guard isReady, isWritable, ftsNeedsRebuild else { return }

        do {
            try execute("INSERT INTO files_fts(files_fts) VALUES ('rebuild')")
            try execute("INSERT INTO files_fts(files_fts) VALUES ('integrity-check')")
            try execute(
                "INSERT INTO metadata(key, value) VALUES ('fts_version', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                bindings: [.text(Self.currentFTSVersion)]
            )
            ftsNeedsRebuild = false
            ftsAvailable = true
            AppLogger.database.info("SQLite FTS5 trigram index is ready")
        } catch {
            ftsAvailable = false
            AppLogger.database.warning("SQLite FTS5 rebuild failed; continuing with fallback search: \(String(describing: error), privacy: .public)")
        }
    }

    var needsSearchAcceleration: Bool {
        ftsNeedsRebuild
    }

    func search(_ query: SearchQuery, ftsAvailableOverride: Bool? = nil) -> [FileRecord] {
        guard isReady else { return [] }

        do {
            let terms = query.normalizedTerms
            let pathTerms = query.normalizedPathTerms
            let primaryTerm = terms.first
            let useFTS = terms.count == 1
                && pathTerms.isEmpty
                && Self.canUseFastFTS(
                    term: primaryTerm ?? "",
                    available: ftsAvailableOverride ?? ftsAvailable
                )
            var selectRelevance = "0"
            var bindings: [SQLiteValue] = []

            if let primaryTerm {
                selectRelevance =
                    """
                    CASE
                        WHEN f.normalized_filename = ? THEN 0
                        WHEN substr(f.normalized_filename, 1, length(?)) = ? THEN 1
                        WHEN instr(f.normalized_filename, ?) > 0 THEN 2
                        WHEN instr(f.normalized_path, ?) > 0 THEN 3
                        ELSE 4
                    END
                    """
                bindings += [
                    .text(primaryTerm),
                    .text(primaryTerm),
                    .text(primaryTerm),
                    .text(primaryTerm),
                    .text(primaryTerm)
                ]
            }

            var sql =
                "SELECT f.id, f.filename, f.full_path, f.extension, f.is_directory, "
                + "f.file_size, f.modification_date, f.last_used_at, \(selectRelevance) AS relevance "
                + "FROM files f "
            var predicates = ["1 = 1"]

            if useFTS, let primaryTerm {
                sql += " JOIN files_fts ON files_fts.rowid = f.id "
                predicates.append("files_fts MATCH ?")
                let escaped = primaryTerm.replacingOccurrences(of: "\"", with: "\"\"")
                bindings.append(.text("\"\(escaped)\""))
            }

            if !useFTS {
                for term in terms {
                    predicates.append("(instr(f.normalized_filename, ?) > 0 OR instr(f.normalized_path, ?) > 0)")
                    bindings += [.text(term), .text(term)]
                }
            }

            for pathTerm in pathTerms {
                predicates.append("instr(f.normalized_path, ?) > 0")
                bindings.append(.text(pathTerm))
            }

            let filenameRegex = query.filenameRegex.trimmingCharacters(in: .whitespacesAndNewlines)
            if !filenameRegex.isEmpty {
                predicates.append("regexp(?, f.filename) != 0")
                bindings.append(.text(filenameRegex))
            }

            let pathRegex = query.pathRegex.trimmingCharacters(in: .whitespacesAndNewlines)
            if !pathRegex.isEmpty {
                predicates.append("regexp(?, f.full_path) != 0")
                bindings.append(.text(pathRegex))
            }

            switch query.kind {
            case .all:
                break
            case .files:
                predicates.append("f.is_directory = 0")
            case .folders:
                predicates.append("f.is_directory = 1")
            }

            switch query.category {
            case .all:
                break
            case .files, .folders:
                // The category buttons also act as the primary file/folder
                // filter. Keep the legacy kind filter above for callers that
                // still construct SearchQuery with only `kind`.
                predicates.append(query.category == .files ? "f.is_directory = 0" : "f.is_directory = 1")
            case .images, .documents, .videos, .audio, .archives:
                predicates.append("f.is_directory = 0")
                let extensions = query.category.extensions ?? []
                let placeholders = Array(repeating: "?", count: extensions.count).joined(separator: ", ")
                predicates.append("f.extension IN (\(placeholders))")
                bindings += extensions.map { .text($0) }
            case .other:
                predicates.append("f.is_directory = 0")
                let extensions = FileCategoryFilter.knownExtensions
                let placeholders = Array(repeating: "?", count: extensions.count).joined(separator: ", ")
                predicates.append("f.extension NOT IN (\(placeholders))")
                bindings += extensions.map { .text($0) }
            }

            if let cutoffDate = query.modificationFilter.cutoffDate {
                predicates.append("f.modification_date >= ?")
                bindings.append(.double(cutoffDate.timeIntervalSince1970))
            }

            let extensionTerm = query.normalizedExtension
            if !extensionTerm.isEmpty {
                predicates.append("f.extension = ?")
                bindings.append(.text(extensionTerm))
            }

            sql += "WHERE " + predicates.joined(separator: " AND ")

            let orderBy: String
            switch query.sort {
            case .relevance:
                orderBy = "relevance ASC, f.last_used_at DESC, f.modification_date DESC, f.filename COLLATE NOCASE ASC"
            case .modifiedNewest:
                orderBy = "f.modification_date DESC, relevance ASC, f.filename COLLATE NOCASE ASC"
            case .modifiedOldest:
                orderBy = "f.modification_date ASC, relevance ASC, f.filename COLLATE NOCASE ASC"
            case .sizeLargest:
                orderBy = "f.file_size DESC, relevance ASC, f.filename COLLATE NOCASE ASC"
            case .sizeSmallest:
                orderBy = "f.file_size ASC, relevance ASC, f.filename COLLATE NOCASE ASC"
            }

            sql += " ORDER BY \(orderBy) LIMIT ?"
            bindings.append(.integer(Int32(max(1, min(query.limit, 1_000)))))

            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            try bind(bindings, to: statement)

            var records: [FileRecord] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                records.append(fileRecord(from: statement))
            }
            return records
        } catch {
            AppLogger.database.error("Search query failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// Calculates the sidebar category totals for the current text/path and
    /// non-category filters. The category itself is intentionally omitted so
    /// every sidebar row describes the same result universe.
    func facetCounts(_ query: SearchQuery, ftsAvailableOverride: Bool? = nil) -> SearchFacetCounts {
        guard isReady else { return SearchFacetCounts() }

        do {
            let imageExtensions = FileCategoryFilter.images.extensions ?? []
            let documentExtensions = FileCategoryFilter.documents.extensions ?? []
            let videoExtensions = FileCategoryFilter.videos.extensions ?? []
            let audioExtensions = FileCategoryFilter.audio.extensions ?? []
            let archiveExtensions = FileCategoryFilter.archives.extensions ?? []
            let knownExtensions = FileCategoryFilter.knownExtensions
            let placeholders: (Int) -> String = { count in
                Array(repeating: "?", count: count).joined(separator: ", ")
            }

            var sql = """
                SELECT
                    COUNT(*),
                    COALESCE(SUM(CASE WHEN f.is_directory = 0 THEN 1 ELSE 0 END), 0),
                    COALESCE(SUM(CASE WHEN f.is_directory = 1 THEN 1 ELSE 0 END), 0),
                    COALESCE(SUM(CASE WHEN f.is_directory = 0 AND f.extension IN (\(placeholders(imageExtensions.count))) THEN 1 ELSE 0 END), 0),
                    COALESCE(SUM(CASE WHEN f.is_directory = 0 AND f.extension IN (\(placeholders(documentExtensions.count))) THEN 1 ELSE 0 END), 0),
                    COALESCE(SUM(CASE WHEN f.is_directory = 0 AND f.extension IN (\(placeholders(videoExtensions.count))) THEN 1 ELSE 0 END), 0),
                    COALESCE(SUM(CASE WHEN f.is_directory = 0 AND f.extension IN (\(placeholders(audioExtensions.count))) THEN 1 ELSE 0 END), 0),
                    COALESCE(SUM(CASE WHEN f.is_directory = 0 AND f.extension IN (\(placeholders(archiveExtensions.count))) THEN 1 ELSE 0 END), 0),
                    COALESCE(SUM(CASE WHEN f.is_directory = 0 AND f.extension NOT IN (\(placeholders(knownExtensions.count))) THEN 1 ELSE 0 END), 0)
                FROM files f
                """

            var bindings: [SQLiteValue] = []
            bindings += imageExtensions.map { .text($0) }
            bindings += documentExtensions.map { .text($0) }
            bindings += videoExtensions.map { .text($0) }
            bindings += audioExtensions.map { .text($0) }
            bindings += archiveExtensions.map { .text($0) }
            bindings += knownExtensions.map { .text($0) }

            let terms = query.normalizedTerms
            let pathTerms = query.normalizedPathTerms
            let primaryTerm = terms.first
            let useFTS = terms.count == 1
                && pathTerms.isEmpty
                && Self.canUseFastFTS(
                    term: primaryTerm ?? "",
                    available: ftsAvailableOverride ?? ftsAvailable
                )
            var predicates = ["1 = 1"]

            if useFTS, let primaryTerm {
                sql += " JOIN files_fts ON files_fts.rowid = f.id "
                predicates.append("files_fts MATCH ?")
                let escaped = primaryTerm.replacingOccurrences(of: "\"", with: "\"\"")
                bindings.append(.text("\"\(escaped)\""))
            }

            if !useFTS {
                for term in terms {
                    predicates.append("(instr(f.normalized_filename, ?) > 0 OR instr(f.normalized_path, ?) > 0)")
                    bindings += [.text(term), .text(term)]
                }
            }

            for pathTerm in pathTerms {
                predicates.append("instr(f.normalized_path, ?) > 0")
                bindings.append(.text(pathTerm))
            }

            let filenameRegex = query.filenameRegex.trimmingCharacters(in: .whitespacesAndNewlines)
            if !filenameRegex.isEmpty {
                predicates.append("regexp(?, f.filename) != 0")
                bindings.append(.text(filenameRegex))
            }

            let pathRegex = query.pathRegex.trimmingCharacters(in: .whitespacesAndNewlines)
            if !pathRegex.isEmpty {
                predicates.append("regexp(?, f.full_path) != 0")
                bindings.append(.text(pathRegex))
            }

            let extensionTerm = query.normalizedExtension
            if !extensionTerm.isEmpty {
                predicates.append("f.extension = ?")
                bindings.append(.text(extensionTerm))
            }

            if let cutoffDate = query.modificationFilter.cutoffDate {
                predicates.append("f.modification_date >= ?")
                bindings.append(.double(cutoffDate.timeIntervalSince1970))
            }

            sql += " WHERE " + predicates.joined(separator: " AND ")

            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            try bind(bindings, to: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw DatabaseError.execute(lastErrorMessage)
            }

            return SearchFacetCounts(
                total: Int(sqlite3_column_int64(statement, 0)),
                files: Int(sqlite3_column_int64(statement, 1)),
                folders: Int(sqlite3_column_int64(statement, 2)),
                images: Int(sqlite3_column_int64(statement, 3)),
                documents: Int(sqlite3_column_int64(statement, 4)),
                videos: Int(sqlite3_column_int64(statement, 5)),
                audio: Int(sqlite3_column_int64(statement, 6)),
                archives: Int(sqlite3_column_int64(statement, 7)),
                other: Int(sqlite3_column_int64(statement, 8))
            )
        } catch {
            AppLogger.database.error("Cannot calculate search facet counts: \(String(describing: error), privacy: .public)")
            return SearchFacetCounts()
        }
    }

    private static func canUseFastFTS(term: String, available: Bool) -> Bool {
        guard available, term.count >= 3 else { return false }

        // The trigram tokenizer is excellent for ordinary ASCII names, but
        // punctuation-heavy terms and non-ASCII text can be tokenized in a
        // way that makes MATCH silently miss a valid filename. The indexed
        // instr() fallback is the correctness path for those queries.
        return term.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 65...90, 97...122: // 0-9, A-Z, a-z
                return true
            default:
                return false
            }
        }
    }

    func stats() -> IndexStats {
        guard isReady else { return IndexStats() }

        var result = IndexStats()
        do {
            let statement = try prepare(
                "SELECT SUM(CASE WHEN is_directory = 0 THEN 1 ELSE 0 END), SUM(CASE WHEN is_directory = 1 THEN 1 ELSE 0 END), MAX(modification_date) FROM files"
            )
            defer { sqlite3_finalize(statement) }
            if sqlite3_step(statement) == SQLITE_ROW {
                result.fileCount = Int(sqlite3_column_int64(statement, 0))
                result.folderCount = Int(sqlite3_column_int64(statement, 1))
                if sqlite3_column_type(statement, 2) != SQLITE_NULL {
                    result.lastIndexDate = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
                }
            }
        } catch {
            AppLogger.database.error("Cannot calculate index stats: \(String(describing: error), privacy: .public)")
        }

        result.databaseSize = databaseSizeOnDisk()
        return result
    }

    func lastEventID() -> UInt64 {
        guard isReady else { return 0 }
        do {
            let statement = try prepare("SELECT value FROM metadata WHERE key = 'last_event_id'")
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
            return UInt64(textColumn(statement, 0)) ?? 0
        } catch {
            AppLogger.database.error("Cannot load last FSEvents ID: \(String(describing: error), privacy: .public)")
            return 0
        }
    }

    func saveLastEventID(_ eventID: UInt64) throws {
        try requireReady()
        try execute(
            "INSERT INTO metadata(key, value) VALUES ('last_event_id', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            bindings: [.text(String(eventID))]
        )
    }

    private func requireReady() throws {
        guard isReady, connection != nil else {
            throw DatabaseError.unavailable
        }
    }

    private func indexedLocationPaths() throws -> [String] {
        let statement = try prepare("SELECT path FROM indexed_locations")
        defer { sqlite3_finalize(statement) }

        var paths: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            paths.append(textColumn(statement, 0))
        }
        return paths
    }

    private func isPath(_ path: String, inside root: String) -> Bool {
        if root == "/" {
            return path.hasPrefix("/")
        }
        return path == root || path.hasPrefix(root + "/")
    }

    private var lastErrorMessage: String {
        guard let connection else { return "database connection unavailable" }
        return String(cString: sqlite3_errmsg(connection))
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let connection else { throw DatabaseError.unavailable }
        var statement: OpaquePointer?
        let result = sql.withCString { sqlPointer in
            sqlite3_prepare_v2(connection, sqlPointer, -1, &statement, nil)
        }
        guard result == SQLITE_OK, let statement else {
            throw DatabaseError.prepare(lastErrorMessage)
        }
        return statement
    }

    private func bind(_ values: [SQLiteValue], to statement: OpaquePointer) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .text(let value):
                result = value.withCString { nfs_sqlite_bind_text_copy(statement, index, $0) }
            case .integer(let value):
                result = sqlite3_bind_int(statement, index, value)
            case .int64(let value):
                result = sqlite3_bind_int64(statement, index, value)
            case .double(let value):
                result = sqlite3_bind_double(statement, index, value)
            }
            guard result == SQLITE_OK else {
                throw DatabaseError.bind(lastErrorMessage)
            }
        }
    }

    private func stepToDone(_ statement: OpaquePointer) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            throw DatabaseError.execute(lastErrorMessage)
        }
    }

    private func execute(_ sql: String, bindings: [SQLiteValue] = []) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        try stepToDone(statement)
    }

    private func transaction(_ operation: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try operation()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func deleteSubtree(path: String) throws {
        if path == "/" {
            try execute("DELETE FROM files")
            return
        }

        try execute(
            "DELETE FROM files WHERE full_path = ? OR substr(full_path, 1, length(?) + 1) = ? || '/'",
            bindings: [.text(path), .text(path), .text(path)]
        )
    }

    private func textColumn(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: UnsafeRawPointer(pointer).assumingMemoryBound(to: CChar.self))
    }

    private func fileRecord(from statement: OpaquePointer) -> FileRecord {
        let lastUsedDate: Date?
        if sqlite3_column_type(statement, 7) == SQLITE_NULL {
            lastUsedDate = nil
        } else {
            lastUsedDate = Date(timeIntervalSince1970: sqlite3_column_double(statement, 7))
        }

        return FileRecord(
            id: sqlite3_column_int64(statement, 0),
            filename: textColumn(statement, 1),
            fullPath: textColumn(statement, 2),
            fileExtension: textColumn(statement, 3),
            isDirectory: sqlite3_column_int(statement, 4) != 0,
            fileSize: sqlite3_column_int64(statement, 5),
            modificationDate: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
            lastUsedDate: lastUsedDate
        )
    }

    private func databaseSizeOnDisk() -> Int64 {
        guard !isInMemory else { return 0 }
        let paths = [
            databaseURL.path,
            databaseURL.path + "-wal",
            databaseURL.path + "-shm"
        ]
        return paths.reduce(into: Int64(0)) { total, path in
            if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
               let size = attributes[.size] as? NSNumber {
                total += size.int64Value
            }
        }
    }

    private static func configure(connection: OpaquePointer) throws -> FTSSetup {
        let schemaVersion = try scalarInt(connection: connection, sql: "PRAGMA user_version")
        let statements = [
            "PRAGMA journal_mode = WAL",
            "PRAGMA synchronous = NORMAL",
            "PRAGMA temp_store = MEMORY",
            "PRAGMA foreign_keys = ON",
            "PRAGMA busy_timeout = 2500",
            """
            CREATE TABLE IF NOT EXISTS metadata(
                key TEXT PRIMARY KEY NOT NULL,
                value TEXT NOT NULL
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS indexed_locations(
                path TEXT PRIMARY KEY NOT NULL,
                is_paused INTEGER NOT NULL DEFAULT 0,
                is_offline INTEGER NOT NULL DEFAULT 0,
                last_scan_at REAL,
                file_count INTEGER NOT NULL DEFAULT 0
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS files(
                id INTEGER PRIMARY KEY,
                filename TEXT NOT NULL,
                full_path TEXT NOT NULL UNIQUE,
                extension TEXT NOT NULL DEFAULT '',
                is_directory INTEGER NOT NULL DEFAULT 0,
                file_size INTEGER NOT NULL DEFAULT 0,
                modification_date REAL NOT NULL DEFAULT 0,
                parent_path TEXT NOT NULL,
                normalized_filename TEXT NOT NULL,
                normalized_path TEXT NOT NULL,
                root_path TEXT NOT NULL,
                last_seen_generation INTEGER NOT NULL DEFAULT 0,
                last_used_at REAL
            )
            """,
            // instr() substring searches cannot use ordinary B-tree indexes.
            // FTS5 handles eligible ASCII terms, while the normalized columns
            // remain the correctness fallback for Unicode and punctuation.
            "DROP INDEX IF EXISTS idx_files_normalized_filename",
            "DROP INDEX IF EXISTS idx_files_normalized_path",
            "CREATE INDEX IF NOT EXISTS idx_files_extension ON files(extension)",
            "CREATE INDEX IF NOT EXISTS idx_files_modification_date ON files(modification_date)",
            "CREATE INDEX IF NOT EXISTS idx_files_file_size ON files(file_size)",
            // parent_path is retained for metadata/display, but no query
            // filters on it. Avoid paying for a large redundant index.
            "DROP INDEX IF EXISTS idx_files_root_parent",
            "CREATE INDEX IF NOT EXISTS idx_files_root_generation ON files(root_path, last_seen_generation)"
        ]

        for statement in statements {
            try execute(connection: connection, sql: statement)
        }

        if !(try hasColumn(connection: connection, table: "indexed_locations", column: "is_offline")) {
            try execute(
                connection: connection,
                sql: "ALTER TABLE indexed_locations ADD COLUMN is_offline INTEGER NOT NULL DEFAULT 0"
            )
        }
        if schemaVersion < Self.currentSchemaVersion {
            try execute(
                connection: connection,
                sql: "PRAGMA user_version = \(Self.currentSchemaVersion)"
            )
        }

        do {
            let ftsVersion = try scalarText(
                connection: connection,
                sql: "SELECT value FROM metadata WHERE key = 'fts_version'"
            )
            let tableExists = try hasTable(connection: connection, table: "files_fts")
            let triggersExist = try [
                "files_after_insert",
                "files_after_delete",
                "files_after_update"
            ].allSatisfy { try hasTrigger(connection: connection, trigger: $0) }
            var needsRebuild = ftsVersion != Self.currentFTSVersion || !tableExists || !triggersExist

            if !needsRebuild {
                do {
                    try execute(
                        connection: connection,
                        sql: "INSERT INTO files_fts(files_fts) VALUES ('integrity-check')"
                    )
                } catch {
                    AppLogger.database.warning("SQLite FTS5 integrity check failed; rebuilding the index: \(String(describing: error), privacy: .public)")
                    needsRebuild = true
                }
            }

            if needsRebuild {
                try execute(connection: connection, sql: "DROP TRIGGER IF EXISTS files_after_insert")
                try execute(connection: connection, sql: "DROP TRIGGER IF EXISTS files_after_delete")
                try execute(connection: connection, sql: "DROP TRIGGER IF EXISTS files_after_update")
                try execute(connection: connection, sql: "DROP TABLE IF EXISTS files_fts")
            }
            try execute(
                connection: connection,
                sql: "CREATE VIRTUAL TABLE IF NOT EXISTS files_fts USING fts5(normalized_filename, normalized_path, content='files', content_rowid='id', tokenize='trigram')"
            )
            try execute(
                connection: connection,
                sql: """
                CREATE TRIGGER IF NOT EXISTS files_after_insert AFTER INSERT ON files BEGIN
                    INSERT INTO files_fts(rowid, normalized_filename, normalized_path)
                    VALUES (new.id, new.normalized_filename, new.normalized_path);
                END
                """
            )
            try execute(
                connection: connection,
                sql: """
                CREATE TRIGGER IF NOT EXISTS files_after_delete AFTER DELETE ON files BEGIN
                    INSERT INTO files_fts(files_fts, rowid, normalized_filename, normalized_path)
                    VALUES ('delete', old.id, old.normalized_filename, old.normalized_path);
                END
                """
            )
            try execute(
                connection: connection,
                sql: """
                CREATE TRIGGER IF NOT EXISTS files_after_update AFTER UPDATE OF filename, full_path ON files BEGIN
                    INSERT INTO files_fts(files_fts, rowid, normalized_filename, normalized_path)
                    VALUES ('delete', old.id, old.normalized_filename, old.normalized_path);
                    INSERT INTO files_fts(rowid, normalized_filename, normalized_path)
                    VALUES (new.id, new.normalized_filename, new.normalized_path);
                END
                """
            )

            return FTSSetup(available: true, needsRebuild: needsRebuild)
        } catch {
            AppLogger.database.warning("FTS5 trigram index unavailable; using indexed SQLite fallback: \(String(describing: error), privacy: .public)")
            return FTSSetup(available: false, needsRebuild: false)
        }
    }

    private static func execute(connection: OpaquePointer, sql: String) throws {
        var statement: OpaquePointer?
        let result = sql.withCString { sqlPointer in
            sqlite3_prepare_v2(connection, sqlPointer, -1, &statement, nil)
        }
        guard result == SQLITE_OK, let statement else {
            throw DatabaseError.prepare(String(cString: sqlite3_errmsg(connection)))
        }
        defer { sqlite3_finalize(statement) }
        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE || stepResult == SQLITE_ROW else {
            throw DatabaseError.execute(String(cString: sqlite3_errmsg(connection)))
        }
    }

    private static func scalarInt(connection: OpaquePointer, sql: String) throws -> Int64 {
        var statement: OpaquePointer?
        let result = sql.withCString { sqlPointer in
            sqlite3_prepare_v2(connection, sqlPointer, -1, &statement, nil)
        }
        guard result == SQLITE_OK, let statement else {
            throw DatabaseError.prepare(String(cString: sqlite3_errmsg(connection)))
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw DatabaseError.execute(String(cString: sqlite3_errmsg(connection)))
        }
        return sqlite3_column_int64(statement, 0)
    }

    private static func scalarText(connection: OpaquePointer, sql: String) throws -> String? {
        var statement: OpaquePointer?
        let result = sql.withCString { sqlPointer in
            sqlite3_prepare_v2(connection, sqlPointer, -1, &statement, nil)
        }
        guard result == SQLITE_OK, let statement else {
            throw DatabaseError.prepare(String(cString: sqlite3_errmsg(connection)))
        }
        defer { sqlite3_finalize(statement) }

        let stepResult = sqlite3_step(statement)
        if stepResult == SQLITE_DONE {
            return nil
        }
        guard stepResult == SQLITE_ROW else {
            throw DatabaseError.execute(String(cString: sqlite3_errmsg(connection)))
        }
        guard let pointer = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: UnsafeRawPointer(pointer).assumingMemoryBound(to: CChar.self))
    }

    private static func hasTable(connection: OpaquePointer, table: String) throws -> Bool {
        try hasSchemaObject(connection: connection, type: "table", name: table)
    }

    private static func hasTrigger(connection: OpaquePointer, trigger: String) throws -> Bool {
        try hasSchemaObject(connection: connection, type: "trigger", name: trigger)
    }

    private static func hasSchemaObject(connection: OpaquePointer, type: String, name: String) throws -> Bool {
        let statement = try prepare(
            connection: connection,
            sql: "SELECT 1 FROM sqlite_master WHERE type = ? AND name = ? LIMIT 1"
        )
        defer { sqlite3_finalize(statement) }
        try bind(
            [.text(type), .text(name)],
            to: statement,
            connection: connection
        )
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private static func hasColumn(connection: OpaquePointer, table: String, column: String) throws -> Bool {
        let statement = try prepare(connection: connection, sql: "PRAGMA table_info(\(table))")
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            if textColumn(statement, index: 1) == column {
                return true
            }
        }
        return false
    }

    private static func prepare(connection: OpaquePointer, sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sql.withCString { sqlPointer in
            sqlite3_prepare_v2(connection, sqlPointer, -1, &statement, nil)
        }
        guard result == SQLITE_OK, let statement else {
            throw DatabaseError.prepare(String(cString: sqlite3_errmsg(connection)))
        }
        return statement
    }

    private static func bind(
        _ values: [SQLiteValue],
        to statement: OpaquePointer,
        connection: OpaquePointer
    ) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .text(let value):
                result = value.withCString { nfs_sqlite_bind_text_copy(statement, index, $0) }
            case .integer(let value):
                result = sqlite3_bind_int(statement, index, value)
            case .int64(let value):
                result = sqlite3_bind_int64(statement, index, value)
            case .double(let value):
                result = sqlite3_bind_double(statement, index, value)
            }
            guard result == SQLITE_OK else {
                throw DatabaseError.bind(String(cString: sqlite3_errmsg(connection)))
            }
        }
    }

    private static func textColumn(_ statement: OpaquePointer, index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: UnsafeRawPointer(pointer).assumingMemoryBound(to: CChar.self))
    }

    private static func hasSearchSchema(connection: OpaquePointer) -> Bool {
        var statement: OpaquePointer?
        let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'files' LIMIT 1"
        let result = sql.withCString { sqlPointer in
            sqlite3_prepare_v2(connection, sqlPointer, -1, &statement, nil)
        }
        guard result == SQLITE_OK, let statement else { return false }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private static func readOnlyFTSAvailable(connection: OpaquePointer) -> Bool {
        do {
            guard try scalarText(
                connection: connection,
                sql: "SELECT value FROM metadata WHERE key = 'fts_version'"
            ) == currentFTSVersion,
            try hasTable(connection: connection, table: "files_fts"),
            try [
                "files_after_insert",
                "files_after_delete",
                "files_after_update"
            ].allSatisfy({ try hasTrigger(connection: connection, trigger: $0) }) else {
                return false
            }
            // FTS5's integrity-check command is expressed as an INSERT,
            // which is not valid on a read-only connection. The writer has
            // already completed that check before publishing fts_version.
            let statement = try prepare(
                connection: connection,
                sql: "SELECT rowid FROM files_fts LIMIT 1"
            )
            defer { sqlite3_finalize(statement) }
            let stepResult = sqlite3_step(statement)
            guard stepResult == SQLITE_ROW || stepResult == SQLITE_DONE else {
                return false
            }
            return true
        } catch {
            AppLogger.database.warning("Read-only FTS5 index is unavailable: \(String(describing: error), privacy: .public)")
            return false
        }
    }
}
