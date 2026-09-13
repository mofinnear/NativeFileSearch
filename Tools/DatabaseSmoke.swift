import Foundation

@main
struct DatabaseSmoke {
    static func main() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("NativeFileSearchSmoke-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let database = FileDatabase(databaseURL: URL(fileURLWithPath: ":memory:"))
        try await database.addIndexedLocation(path: root.path)
        let generation = try await database.beginGeneration()

        let sampleCount = 2_000
        var records: [FileMetadata] = []
        records.reserveCapacity(sampleCount + 1)
        records.append(try FileMetadata(url: root, rootPath: root.path))

        let localizedFile = root.appendingPathComponent("项目合同12-1101.pdf")
        try Data("smoke".utf8).write(to: localizedFile)
        records.append(try FileMetadata(url: localizedFile, rootPath: root.path))

        let compoundSearchFile = root.appendingPathComponent("12-3.jpg")
        try Data("smoke".utf8).write(to: compoundSearchFile)
        records.append(try FileMetadata(url: compoundSearchFile, rootPath: root.path))

        let multiTermSearchFile = root.appendingPathComponent("张三小区27栋5单元201.jpg")
        try Data("smoke".utf8).write(to: multiTermSearchFile)
        records.append(try FileMetadata(url: multiTermSearchFile, rootPath: root.path))

        for index in 0..<sampleCount {
            let folder = root.appendingPathComponent("project-\(index % 10)", isDirectory: true)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            if index < 10 {
                records.append(try FileMetadata(url: folder, rootPath: root.path))
            }
            let file = folder.appendingPathComponent("Quarterly-Report-\(index).pdf")
            try Data("smoke".utf8).write(to: file)
            records.append(try FileMetadata(url: file, rootPath: root.path))
        }

        let batchSize = 250
        for start in stride(from: 0, to: records.count, by: batchSize) {
            let end = min(start + batchSize, records.count)
            try await database.upsert(Array(records[start..<end]), generation: generation)
        }
        try await database.finishScan(rootPath: root.path, scanDate: Date())
        await database.prepareSearchAcceleration()
        let ftsReady = await database.ftsAvailable
        guard ftsReady else {
            throw SmokeFailure(message: "FTS5 acceleration was not prepared")
        }

        let clockStart = ContinuousClock.now
        let results = await database.search(
            SearchQuery(text: "Quarterly-Report-19.pdf", extensionFilter: "pdf", kind: .files, sort: .relevance)
        )
        let elapsed = clockStart.duration(to: .now)

        guard let firstResult = results.first,
              firstResult.filename == "Quarterly-Report-19.pdf" else {
            throw SmokeFailure(message: "unexpected search result set: count=\(results.count), names=\(results.prefix(5).map { $0.filename })")
        }

        let folders = await database.search(
            SearchQuery(text: "project-1", extensionFilter: "", kind: .folders, sort: .relevance)
        )
        guard folders.count == 1, folders[0].filename == "project-1" else {
            throw SmokeFailure(message: "folder filter did not return one folder: count=\(folders.count), names=\(folders.prefix(5).map { $0.filename })")
        }

        let chineseResults = await database.search(
            SearchQuery(text: "项目", extensionFilter: "", kind: .files, sort: .relevance)
        )
        guard chineseResults.contains(where: { $0.filename == "项目合同12-1101.pdf" }) else {
            throw SmokeFailure(message: "Chinese filename search did not find the localized file")
        }

        let numericResults = await database.search(
            SearchQuery(text: "12-", extensionFilter: "", kind: .files, sort: .relevance)
        )
        guard numericResults.contains(where: { $0.filename == "项目合同12-1101.pdf" }) else {
            throw SmokeFailure(message: "Numeric filename search did not find the localized file")
        }

        let compoundResults = await database.search(
            SearchQuery(text: "12-3 jpg", extensionFilter: "", kind: .all, sort: .relevance)
        )
        guard compoundResults.count == 1,
              compoundResults[0].filename == "12-3.jpg" else {
            let names = compoundResults.map { $0.filename }.joined(separator: ", ")
            throw SmokeFailure(message: "Combined filename and extension search returned " + names)
        }

        let multiTermResults = await database.search(
            SearchQuery(text: "张三小区 201", extensionFilter: "", kind: .files, sort: .relevance)
        )
        guard multiTermResults.count == 1,
              multiTermResults[0].filename == "张三小区27栋5单元201.jpg" else {
            throw SmokeFailure(message: "Multi-term localized search returned (multiTermResults.map { $0.filename })")
        }

        let explicitTypeResults = await database.search(
            SearchQuery(text: "12-3 type:jpg", extensionFilter: "", kind: .files, sort: .relevance)
        )
        guard explicitTypeResults.count == 1,
              explicitTypeResults[0].filename == "12-3.jpg" else {
            throw SmokeFailure(message: "Explicit type filter returned (explicitTypeResults.map { $0.filename })")
        }

        let regexResults = await database.search(
            SearchQuery(
                text: "",
                extensionFilter: "pdf",
                kind: .files,
                sort: .relevance,
                filenameRegex: "Quarterly-Report-19\\.pdf",
                pathRegex: "project-9"
            )
        )
        guard regexResults.count == 1,
              regexResults[0].filename == "Quarterly-Report-19.pdf" else {
            throw SmokeFailure(message: "Advanced regex search returned \(regexResults.map { $0.filename })")
        }

        let localizedRegexResults = await database.search(
            SearchQuery(
                text: "",
                extensionFilter: "pdf",
                kind: .files,
                sort: .relevance,
                filenameRegex: "项目|合同",
                pathRegex: "NativeFileSearchSmoke"
            )
        )
        guard localizedRegexResults.contains(where: { $0.filename == "项目合同12-1101.pdf" }) else {
            throw SmokeFailure(message: "Localized advanced regex search did not find the Chinese filename")
        }

        let unicodeRegexResults = await database.search(
            SearchQuery(
                text: "",
                extensionFilter: "pdf",
                kind: .files,
                sort: .relevance,
                filenameRegex: "^项目.*12-[0-9]+\\.pdf$"
            )
        )
        guard unicodeRegexResults.contains(where: { $0.filename == "项目合同12-1101.pdf" }) else {
            throw SmokeFailure(message: "UTF-8 regex matching did not find the localized filename")
        }

        let pathResults = await database.search(
            SearchQuery(text: "path:project-7 type:pdf", extensionFilter: "", kind: .files, sort: .relevance)
        )
        guard pathResults.count == 200,
              pathResults.allSatisfy({ $0.fullPath.contains("/project-7/") && $0.fileExtension == "pdf" }) else {
            throw SmokeFailure(message: "Combined path/type search returned (pathResults.count) results")
        }

        let documentResults = await database.search(
            SearchQuery(
                text: "",
                extensionFilter: "",
                kind: .all,
                sort: .relevance,
                category: .documents,
                modificationFilter: .today
            )
        )
        guard documentResults.count == 250,
              documentResults.allSatisfy({ !$0.isDirectory && $0.fileExtension == "pdf" }) else {
            throw SmokeFailure(message: "Document category or modification-time filter returned \(documentResults.count) results")
        }

        let localizedFacets = await database.facetCounts(
            SearchQuery(text: "项目", extensionFilter: "", kind: .all, sort: .relevance)
        )
        guard localizedFacets.total == 1,
              localizedFacets.files == 1,
              localizedFacets.folders == 0,
              localizedFacets.documents == 1 else {
            throw SmokeFailure(message: "Localized facet counts were incorrect: \(localizedFacets)")
        }

        let pdfFacets = await database.facetCounts(
            SearchQuery(text: "", extensionFilter: "pdf", kind: .all, sort: .relevance)
        )
        guard pdfFacets.total == sampleCount + 1,
              pdfFacets.files == sampleCount + 1,
              pdfFacets.folders == 0,
              pdfFacets.documents == sampleCount + 1 else {
            throw SmokeFailure(message: "Extension facet counts were incorrect: \(pdfFacets)")
        }

        let asciiFacets = await database.facetCounts(
            SearchQuery(text: "Quarterly", extensionFilter: "", kind: .all, sort: .relevance)
        )
        guard asciiFacets.total == sampleCount,
              asciiFacets.files == sampleCount,
              asciiFacets.documents == sampleCount else {
            throw SmokeFailure(message: "ASCII facet counts were incorrect: \(asciiFacets)")
        }

        try await database.deletePath(root.appendingPathComponent("project-1").path)
        let deletedResults = await database.search(
            SearchQuery(text: "Quarterly-Report-11.pdf", extensionFilter: "pdf", kind: .files, sort: .relevance)
        )
        guard deletedResults.isEmpty else {
            throw SmokeFailure(message: "subtree deletion left stale rows: \(deletedResults.prefix(5).map { $0.fullPath })")
        }

        print("NativeFileSearch database smoke passed: \(sampleCount) files, query \(elapsed), FTS \(ftsReady ? "ready" : "fallback")")
    }
}

private struct SmokeFailure: Error, LocalizedError {
    let message: String

    var errorDescription: String? { message }
}
