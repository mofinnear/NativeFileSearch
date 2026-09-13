import Foundation

@main
struct DiskPersistenceSmoke {
    static func main() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("NativeFileSearchDiskSmoke-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let file = root.appendingPathComponent("Persistent Résumé.txt")
        try Data("persistent".utf8).write(to: file)
        let databaseURL = root.appendingPathComponent("index.sqlite")

        do {
            let database = FileDatabase(databaseURL: databaseURL)
            try await database.addIndexedLocation(path: root.path)
            let generation = try await database.beginGeneration()
            try await database.upsert(
                [
                    FileMetadata(url: root, rootPath: root.path),
                    FileMetadata(url: file, rootPath: root.path)
                ],
                generation: generation
            )
            try await database.finishScan(rootPath: root.path, scanDate: Date())
            await database.prepareSearchAcceleration()
        }

        do {
            let database = FileDatabase(databaseURL: databaseURL)
            let searchEngine = SearchEngine(database: database, databaseURL: databaseURL)
            let results = await searchEngine.search(
                SearchQuery(text: "persistent resume", extensionFilter: "txt", kind: .files, sort: .relevance)
            )
            let fastResults = await searchEngine.search(
                SearchQuery(text: "persistent", extensionFilter: "txt", kind: .files, sort: .relevance)
            )
            let fastFacets = await searchEngine.facetCounts(
                SearchQuery(text: "persistent", extensionFilter: "", kind: .all, sort: .relevance)
            )
            let stats = await database.stats()
            let ftsReady = await database.ftsAvailable
            guard results.first?.filename == "Persistent Résumé.txt",
                  fastResults.first?.filename == "Persistent Résumé.txt",
                  fastFacets.total == 1,
                  stats.databaseSize > 0 else {
                throw SmokeFailure(message: "disk database did not persist searchable rows")
            }
            print("NativeFileSearch disk persistence FTS: \(ftsReady ? "ready" : "fallback")")
        }

        print("NativeFileSearch disk persistence smoke passed")
    }
}

private struct SmokeFailure: Error, LocalizedError {
    let message: String

    var errorDescription: String? { message }
}
