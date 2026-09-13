import Foundation
import XCTest

@testable import NativeFileSearch

final class FileDatabaseTests: XCTestCase {
    func testUpsertAndSearchByName() async throws {
        let database = FileDatabase(databaseURL: URL(fileURLWithPath: ":memory:"))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NativeFileSearchTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = root.appendingPathComponent("Quarterly Report.PDF")

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("test".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: root) }

        try await database.addIndexedLocation(path: root.path)
        let generation = try await database.beginGeneration()
        let rootMetadata = try FileMetadata(url: root, rootPath: root.path)
        let fileMetadata = try FileMetadata(url: fileURL, rootPath: root.path)
        try await database.upsert([rootMetadata, fileMetadata], generation: generation)

        let results = await database.search(
            SearchQuery(text: "quarterly", extensionFilter: "pdf", kind: .files, sort: .relevance)
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.filename, "Quarterly Report.PDF")
        XCTAssertEqual(results.first?.fileExtension, "pdf")
    }
}
