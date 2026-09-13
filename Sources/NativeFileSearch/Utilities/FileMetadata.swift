import Foundation

struct FileMetadata: Sendable {
    let filename: String
    let fullPath: String
    let fileExtension: String
    let isDirectory: Bool
    let fileSize: Int64
    let modificationDate: Date
    let parentPath: String
    let normalizedFilename: String
    let normalizedPath: String
    let rootPath: String

    init(url: URL, rootPath: String) throws {
        try self.init(url: url, rootPath: rootPath, resourceValues: nil)
    }

    init(
        url: URL,
        rootPath: String,
        resourceValues: URLResourceValues?
    ) throws {
        let standardizedURL = url.standardizedFileURL
        let values: URLResourceValues
        if let resourceValues {
            values = resourceValues
        } else {
            values = try standardizedURL.resourceValues(forKeys: [
                .nameKey,
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
                .contentModificationDateKey
            ])
        }

        if values.isSymbolicLink == true {
            throw MetadataError.symbolicLink
        }

        let path = standardizedURL.path
        let name = values.name ?? standardizedURL.lastPathComponent
        let directory = values.isDirectory ?? false

        self.filename = name
        self.fullPath = path
        self.fileExtension = directory ? "" : standardizedURL.pathExtension.nfsNormalizedSearchText
        self.isDirectory = directory
        self.fileSize = directory ? 0 : max(0, Int64(values.fileSize ?? 0))
        self.modificationDate = values.contentModificationDate ?? .distantPast
        self.parentPath = standardizedURL.deletingLastPathComponent().path
        self.normalizedFilename = name.nfsNormalizedSearchText
        self.normalizedPath = path.nfsNormalizedSearchText
        self.rootPath = URL(fileURLWithPath: rootPath).standardizedFileURL.path
    }

    enum MetadataError: Error {
        case symbolicLink
    }
}
