import CoreServices
import Foundation

@main
struct IndexerSmoke {
    static func main() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("NativeFileSearchIndexerSmoke-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let database = FileDatabase(databaseURL: URL(fileURLWithPath: ":memory:"))
        try await database.addIndexedLocation(path: root.path)

        let indexer = FileIndexer(database: database)
        await indexer.setIndexedLocations([IndexedLocation(path: root.path)])

        let initialFile = root.appendingPathComponent("initial.txt")
        try Data("initial".utf8).write(to: initialFile)
        await indexer.indexAll()
        try await requireSearch(database, text: "initial.txt", message: "initial scan")

        let createdFile = root.appendingPathComponent("created.md")
        try Data("created".utf8).write(to: createdFile)
        await indexer.handle(
            FileSystemChange(
                path: createdFile.path,
                flags: UInt32(kFSEventStreamEventFlagItemCreated),
                eventID: 1
            )
        )
        await waitForCoalescedChanges()
        try await requireSearch(database, text: "created.md", message: "incremental create")

        let atomicallyReplacedFile = root.appendingPathComponent("atomically-replaced.txt")
        try Data("atomic".utf8).write(to: atomicallyReplacedFile)
        await indexer.handle(
            FileSystemChange(
                path: atomicallyReplacedFile.path,
                flags: UInt32(kFSEventStreamEventFlagItemCreated)
                    | UInt32(kFSEventStreamEventFlagItemRemoved)
                    | UInt32(kFSEventStreamEventFlagItemRenamed),
                eventID: 2
            )
        )
        await waitForCoalescedChanges()
        try await requireSearch(
            database,
            text: "atomically-replaced.txt",
            message: "merged create/remove event"
        )

        let renamedFile = root.appendingPathComponent("renamed.md")
        try fileManager.moveItem(at: createdFile, to: renamedFile)
        await indexer.handle(
            FileSystemChange(
                path: createdFile.path,
                flags: UInt32(kFSEventStreamEventFlagItemRemoved),
                eventID: 3
            )
        )
        await indexer.handle(
            FileSystemChange(
                path: renamedFile.path,
                flags: UInt32(kFSEventStreamEventFlagItemCreated),
                eventID: 4
            )
        )
        await waitForCoalescedChanges()
        try await requireSearch(database, text: "renamed.md", message: "incremental rename")
        try await requireNoSearch(database, text: "created.md", message: "old rename path")

        try fileManager.removeItem(at: renamedFile)
        await indexer.handle(
            FileSystemChange(
                path: renamedFile.path,
                flags: UInt32(kFSEventStreamEventFlagItemRemoved),
                eventID: 5
            )
        )
        await waitForCoalescedChanges()
        try await requireNoSearch(database, text: "renamed.md", message: "incremental delete")

        let recoveredFile = root.appendingPathComponent("recovered.log")
        try Data("recovered".utf8).write(to: recoveredFile)
        await indexer.handle(
            FileSystemChange(
                path: root.path,
                flags: UInt32(kFSEventStreamEventFlagMustScanSubDirs),
                eventID: 6
            )
        )
        await waitForCoalescedChanges()
        try await requireSearch(database, text: "recovered.log", message: "dropped-event recovery scan")

        try fileManager.removeItem(at: root)
        await indexer.handle(
            FileSystemChange(
                path: root.path,
                flags: UInt32(kFSEventStreamEventFlagRootChanged)
                    | UInt32(kFSEventStreamEventFlagItemRemoved),
                eventID: 7
            )
        )
        await waitForCoalescedChanges()
        try await requireSearch(
            database,
            text: "initial.txt",
            message: "offline root preservation"
        )

        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let reappearedFile = root.appendingPathComponent("reappeared.txt")
        try Data("reappeared".utf8).write(to: reappearedFile)
        await indexer.handle(
            FileSystemChange(
                path: root.path,
                flags: UInt32(kFSEventStreamEventFlagRootChanged),
                eventID: 8
            )
        )
        await waitForCoalescedChanges()
        try await requireSearch(
            database,
            text: "reappeared.txt",
            message: "offline root rescan"
        )

        print("NativeFileSearch indexer smoke passed: create, rename, delete, recovery, atomic replacement, and offline root handling")
    }

    private static func waitForCoalescedChanges() async {
        try? await Task.sleep(nanoseconds: 450_000_000)
    }

    private static func requireSearch(
        _ database: FileDatabase,
        text: String,
        message: String
    ) async throws {
        let results = await database.search(
            SearchQuery(text: text, extensionFilter: "", kind: .all, sort: .relevance)
        )
        guard !results.isEmpty else {
            throw SmokeFailure(message: "\(message) did not find \(text)")
        }
    }

    private static func requireNoSearch(
        _ database: FileDatabase,
        text: String,
        message: String
    ) async throws {
        let results = await database.search(
            SearchQuery(text: text, extensionFilter: "", kind: .all, sort: .relevance)
        )
        guard results.isEmpty else {
            throw SmokeFailure(message: "\(message) kept stale result for \(text)")
        }
    }
}

private struct SmokeFailure: Error, LocalizedError {
    let message: String

    var errorDescription: String? { message }
}
