import Foundation

struct FileRecord: Identifiable, Hashable, Sendable {
    let id: Int64
    let filename: String
    let fullPath: String
    let fileExtension: String
    let isDirectory: Bool
    let fileSize: Int64
    let modificationDate: Date
    let lastUsedDate: Date?

    var fileTypeLabel: String {
        if isDirectory {
            return NFSLocalized.text("文件夹", "Folder")
        }

        guard !fileExtension.isEmpty else {
            return NFSLocalized.text("文件", "File")
        }

        return NFSLocalized.text(
            ".\(fileExtension.uppercased()) 文件",
            ".\(fileExtension.uppercased()) file"
        )
    }
}

enum FileKindFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case files
    case folders

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return NFSLocalized.text("全部", "All")
        case .files: return NFSLocalized.text("文件", "Files")
        case .folders: return NFSLocalized.text("文件夹", "Folders")
        }
    }
}

enum FileCategoryFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case files
    case folders
    case images
    case documents
    case videos
    case audio
    case archives
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return NFSLocalized.text("全部", "All")
        case .files: return NFSLocalized.text("文件", "Files")
        case .folders: return NFSLocalized.text("文件夹", "Folders")
        case .images: return NFSLocalized.text("图片", "Images")
        case .documents: return NFSLocalized.text("文档", "Documents")
        case .videos: return NFSLocalized.text("视频", "Videos")
        case .audio: return NFSLocalized.text("音频", "Audio")
        case .archives: return NFSLocalized.text("压缩包", "Archives")
        case .other: return NFSLocalized.text("其他", "Other")
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .files: return "doc"
        case .folders: return "folder"
        case .images: return "photo"
        case .documents: return "doc.text"
        case .videos: return "film"
        case .audio: return "music.note"
        case .archives: return "archivebox"
        case .other: return "ellipsis"
        }
    }

    var fileKind: FileKindFilter {
        switch self {
        case .folders: return .folders
        case .all: return .all
        default: return .files
        }
    }

    var extensions: [String]? {
        switch self {
        case .all, .files, .folders:
            return nil
        case .images:
            return ["jpg", "jpeg", "png", "gif", "heic", "heif", "tif", "tiff", "webp", "svg", "bmp", "raw", "psd", "ai"]
        case .documents:
            return ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "md", "csv", "tsv", "pages", "numbers", "key", "odt"]
        case .videos:
            return ["mp4", "mov", "m4v", "avi", "mkv", "webm", "wmv", "flv"]
        case .audio:
            return ["mp3", "m4a", "aac", "wav", "flac", "ogg", "aiff", "aif"]
        case .archives:
            return ["zip", "rar", "7z", "tar", "gz", "bz2", "xz", "dmg", "iso", "pkg"]
        case .other:
            return nil
        }
    }

    static var knownExtensions: [String] {
        let categories: [FileCategoryFilter] = [.images, .documents, .videos, .audio, .archives]
        return Array(Set(categories.flatMap { $0.extensions ?? [] })).sorted()
    }
}

enum ModificationFilter: String, CaseIterable, Identifiable, Sendable {
    case any
    case today
    case lastSevenDays
    case lastThirtyDays
    case lastYear

    var id: String { rawValue }

    var label: String {
        switch self {
        case .any: return NFSLocalized.text("修改时间", "Modified")
        case .today: return NFSLocalized.text("今天", "Today")
        case .lastSevenDays: return NFSLocalized.text("近 7 天", "Last 7 days")
        case .lastThirtyDays: return NFSLocalized.text("近 30 天", "Last 30 days")
        case .lastYear: return NFSLocalized.text("近一年", "Last year")
        }
    }

    var cutoffDate: Date? {
        let now = Date()
        switch self {
        case .any:
            return nil
        case .today:
            return Calendar.current.startOfDay(for: now)
        case .lastSevenDays:
            return Calendar.current.date(byAdding: .day, value: -7, to: now)
        case .lastThirtyDays:
            return Calendar.current.date(byAdding: .day, value: -30, to: now)
        case .lastYear:
            return Calendar.current.date(byAdding: .year, value: -1, to: now)
        }
    }
}

enum SearchSort: String, CaseIterable, Identifiable, Sendable {
    case relevance
    case modifiedNewest
    case modifiedOldest
    case sizeLargest
    case sizeSmallest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .relevance: return NFSLocalized.text("相关性排序", "Relevance")
        case .modifiedNewest: return NFSLocalized.text("修改时间：最新", "Modified: newest")
        case .modifiedOldest: return NFSLocalized.text("修改时间：最早", "Modified: oldest")
        case .sizeLargest: return NFSLocalized.text("大小：最大", "Size: largest")
        case .sizeSmallest: return NFSLocalized.text("大小：最小", "Size: smallest")
        }
    }
}

struct SearchQuery: Sendable, Equatable {
    var text: String
    var extensionFilter: String
    var kind: FileKindFilter
    var sort: SearchSort
    var category: FileCategoryFilter = .all
    var modificationFilter: ModificationFilter = .any
    var limit: Int = 250
    /// Optional POSIX regular expressions used by the advanced search panel.
    /// They are evaluated inside SQLite through the registered regexp function
    /// so a broad regex never causes the UI to scan the filesystem.
    var filenameRegex: String = ""
    var pathRegex: String = ""

    /// Free-text terms are ANDed together. Each term can match either the
    /// filename or the complete path, which makes inputs such as
    /// "张三小区 201" useful even when the remembered pieces are not next to
    /// each other in the real filename.
    var normalizedTerms: [String] {
        parsedInput.terms
            .map { $0.nfsNormalizedSearchText }
            .filter { !$0.isEmpty }
    }

    /// Explicit path terms only match the indexed path. A leading "~/" is
    /// expanded so users can search with the same shorthand they see in the
    /// Finder and terminal.
    var normalizedPathTerms: [String] {
        parsedInput.pathTerms
            .map(Self.normalizedPathTerm)
            .filter { !$0.isEmpty }
    }

    var normalizedText: String {
        normalizedTerms.joined(separator: " ")
    }

    var normalizedExtension: String {
        let explicitExtension = Self.normalizedExtension(extensionFilter)
        return explicitExtension.isEmpty ? (parsedInput.fileExtension ?? "") : explicitExtension
    }

    /// An empty query deliberately does not mean "show everything". The UI
    /// uses this to keep the initial window quiet until the user enters a
    /// search term or chooses a filter.
    var hasSearchCriteria: Bool {
        !normalizedTerms.isEmpty
            || !normalizedPathTerms.isEmpty
            || !normalizedExtension.isEmpty
            || category != .all
            || kind != .all
            || modificationFilter != .any
            || !filenameRegex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !pathRegex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Supports composable Everything-style input. Whitespace separates AND
    /// terms; known extensions can be written directly ("12-3 jpg"), while
    /// path: and ext:/type: make the intent explicit for paths and uncommon
    /// extensions.
    private var parsedInput: SearchInputParts {
        var terms: [String] = []
        var pathTerms: [String] = []
        var fileExtension: String?

        for rawToken in text.split(whereSeparator: { $0.isWhitespace }) {
            let token = String(rawToken)
            let normalizedToken = token.nfsNormalizedSearchText

            if normalizedToken.hasPrefix("path:") {
                let value = String(token.dropFirst(5))
                if !value.isEmpty {
                    pathTerms.append(value)
                }
                continue
            }

            if normalizedToken.hasPrefix("ext:") {
                let value = Self.normalizedExtension(String(token.dropFirst(4)))
                if !value.isEmpty {
                    fileExtension = value
                }
                continue
            }

            if normalizedToken.hasPrefix("type:") {
                let value = Self.normalizedExtension(String(token.dropFirst(5)))
                if !value.isEmpty {
                    fileExtension = value
                }
                continue
            }

            // A known extension can be written on its own or alongside other
            // terms: "12-3 jpg", "张三小区 201 pdf", or simply "pdf".
            // Unknown extensions remain normal text unless ext:/type: is used,
            // avoiding surprises for names such as ".DS_Store".
            let extensionCandidate = Self.normalizedExtension(token)
            if FileCategoryFilter.knownExtensions.contains(extensionCandidate) {
                fileExtension = extensionCandidate
                continue
            }

            terms.append(token)
        }

        return SearchInputParts(terms: terms, pathTerms: pathTerms, fileExtension: fileExtension)
    }

    private static func normalizedExtension(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .nfsNormalizedSearchText
    }

    private static func normalizedPathTerm(_ value: String) -> String {
        let expandedValue: String
        if value == "~" {
            expandedValue = FileManager.default.homeDirectoryForCurrentUser.path
        } else if value.hasPrefix("~/") {
            expandedValue = FileManager.default.homeDirectoryForCurrentUser.path + String(value.dropFirst())
        } else {
            expandedValue = value
        }
        return expandedValue.nfsNormalizedSearchText
    }
}

private struct SearchInputParts: Sendable, Equatable {
    let terms: [String]
    let pathTerms: [String]
    let fileExtension: String?
}

struct SearchFacetCounts: Sendable, Equatable {
    var total: Int = 0
    var files: Int = 0
    var folders: Int = 0
    var images: Int = 0
    var documents: Int = 0
    var videos: Int = 0
    var audio: Int = 0
    var archives: Int = 0
    var other: Int = 0

    func count(for category: FileCategoryFilter) -> Int {
        switch category {
        case .all: return total
        case .files: return files
        case .folders: return folders
        case .images: return images
        case .documents: return documents
        case .videos: return videos
        case .audio: return audio
        case .archives: return archives
        case .other: return other
        }
    }
}

struct IndexedLocation: Identifiable, Hashable, Sendable {
    let id: String
    let path: String
    var isPaused: Bool
    var isOffline: Bool
    var lastScanDate: Date?
    var fileCount: Int

    init(
        path: String,
        isPaused: Bool = false,
        isOffline: Bool = false,
        lastScanDate: Date? = nil,
        fileCount: Int = 0
    ) {
        self.id = path
        self.path = path
        self.isPaused = isPaused
        self.isOffline = isOffline
        self.lastScanDate = lastScanDate
        self.fileCount = fileCount
    }
}

struct IndexStats: Sendable, Equatable {
    var fileCount: Int = 0
    var folderCount: Int = 0
    var databaseSize: Int64 = 0
    var lastIndexDate: Date?

    var totalCount: Int { fileCount + folderCount }
}

enum IndexingPhase: Equatable, Sendable {
    case idle
    case indexing
    case paused
    case error
}

struct IndexingStatus: Equatable, Sendable {
    var phase: IndexingPhase = .idle
    var currentPath: String?
    var processedCount: Int = 0
    var lastError: String?
}
