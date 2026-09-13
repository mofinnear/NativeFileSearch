import Foundation

/// Query-only façade. It deliberately has no FileManager or FSEvents knowledge.
actor SearchEngine {
    private let database: FileDatabase
    private let readDatabase: FileDatabase?

    init(database: FileDatabase, databaseURL: URL? = nil) {
        self.database = database
        if let databaseURL,
           databaseURL.path != ":memory:",
           databaseURL.lastPathComponent != ":memory:" {
            self.readDatabase = FileDatabase(databaseURL: databaseURL, readOnly: true)
        } else {
            self.readDatabase = nil
        }
    }

    func search(_ query: SearchQuery) async -> [FileRecord] {
        if let readDatabase, await readDatabase.isReady {
            let writerFTSAvailable = await database.ftsAvailable
            return await readDatabase.search(query, ftsAvailableOverride: writerFTSAvailable)
        }
        return await database.search(query)
    }

    func facetCounts(_ query: SearchQuery) async -> SearchFacetCounts {
        if let readDatabase, await readDatabase.isReady {
            let writerFTSAvailable = await database.ftsAvailable
            return await readDatabase.facetCounts(query, ftsAvailableOverride: writerFTSAvailable)
        }
        return await database.facetCounts(query)
    }
}
