import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    let database: FileDatabase
    let indexer: FileIndexer
    let searchEngine: SearchEngine

    @Published var searchText = "" {
        didSet {
            if !isApplyingAdvancedSearch && advancedSearchActive {
                // The advanced dialog writes a readable summary into this
                // field. As soon as the user edits it manually, switch back
                // to ordinary search so the summary is never mistaken for a
                // second set of hidden filters.
                advancedSearchActive = false
                filenameRegex = ""
                pathRegex = ""
                extensionFilter = ""
                categoryFilter = .all
                kindFilter = .all
                modificationFilter = .any
            }
            scheduleSearch()
        }
    }
    @Published var extensionFilter = "" {
        didSet { scheduleSearch() }
    }
    @Published var filenameRegex = "" {
        didSet { scheduleSearch() }
    }
    @Published var pathRegex = "" {
        didSet { scheduleSearch() }
    }
    @Published private(set) var advancedSearchActive = false
    @Published var categoryFilter: FileCategoryFilter = .all {
        didSet { scheduleSearch() }
    }
    @Published var kindFilter: FileKindFilter = .all {
        didSet { scheduleSearch() }
    }
    @Published var modificationFilter: ModificationFilter = .any {
        didSet { scheduleSearch() }
    }
    @Published var sort: SearchSort = .relevance {
        didSet { scheduleSearch() }
    }

    @Published private(set) var results: [FileRecord] = []
    @Published private(set) var lastSearchMilliseconds: Double = 0
    @Published private(set) var facetCounts = SearchFacetCounts()
    @Published var selectedResult: FileRecord?
    @Published private(set) var indexedLocations: [IndexedLocation] = []
    @Published private(set) var stats = IndexStats()
    @Published private(set) var indexingStatus = IndexingStatus()
    @Published var showOnboarding = false
    @Published var pendingTrash: FileRecord?
    @Published var notice: String?

    private let settings = SettingsStore.shared
    private let quickLookPreview = QuickLookPreviewController()
    private var searchTask: Task<Void, Never>?
    private var progressSearchTask: Task<Void, Never>?
    private var lastProgressSearchAt = Date.distantPast
    private var watcher: FileEventWatcher?
    private var progressObserver: NSObjectProtocol?
    private var hotKeyObserver: NSObjectProtocol?
    private var isApplyingAdvancedSearch = false

    init() {
        let databaseURL = SettingsStore.shared.databaseURL()
        let database = FileDatabase(databaseURL: databaseURL)
        self.database = database
        self.indexer = FileIndexer(database: database)
        self.searchEngine = SearchEngine(database: database, databaseURL: databaseURL)

        progressObserver = NotificationCenter.default.addObserver(
            forName: .nfsIndexProgress,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let progress = notification.object as? IndexProgress else { return }
            Task { @MainActor [weak self] in
                self?.apply(progress: progress)
            }
        }

        hotKeyObserver = NotificationCenter.default.addObserver(
            forName: .nfsShowSearchWindow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.showSearchWindow()
            }
        }

        Task { [weak self] in
            await self?.bootstrap()
        }
    }

    deinit {
        searchTask?.cancel()
        progressSearchTask?.cancel()
        if let progressObserver {
            NotificationCenter.default.removeObserver(progressObserver)
        }
        if let hotKeyObserver {
            NotificationCenter.default.removeObserver(hotKeyObserver)
        }
        watcher?.stop()
    }

    func bootstrap() async {
        await refreshLocations()
        await indexer.setIndexedLocations(indexedLocations)

        if await database.needsSearchAcceleration {
            indexingStatus.phase = .indexing
            let preparingNotice = NFSLocalized.text(
                "正在准备搜索索引…",
                "Preparing the search index…"
            )
            notice = preparingNotice
            await database.prepareSearchAcceleration()
            if notice == preparingNotice {
                notice = nil
            }
            indexingStatus.phase = .idle
        }

        await restartWatcher()
        await refreshStats()

        if let startupError = await database.startupError {
            indexingStatus.phase = .error
            indexingStatus.lastError = startupError
            if await database.isWritable {
                notice = NFSLocalized.text(
                    "搜索数据库需要检查，请确认数据库文件权限。",
                    "The search database needs attention. Check its permissions."
                )
            } else {
                notice = NFSLocalized.text(
                    "搜索数据库为只读，现有结果可用，索引更新已暂停。",
                    "The search database is read-only. Existing results are available, but indexing is paused."
                )
            }
        }

        if indexedLocations.isEmpty && !settings.hasCompletedInitialSetup {
            showOnboarding = true
        } else if indexedLocations.contains(where: { !$0.isPaused && $0.lastScanDate == nil }) {
            // A crash or quit during the first scan leaves last_scan_at empty.
            // Resume those roots once, while completed roots continue from FSEvents.
            await indexer.indexAll()
            await refreshLocations()
            await refreshStats()
        }
    }

    private func makeCurrentSearchQuery() -> SearchQuery {
        SearchQuery(
            text: advancedSearchActive ? "" : searchText,
            extensionFilter: extensionFilter,
            kind: categoryFilter == .all ? kindFilter : categoryFilter.fileKind,
            sort: sort,
            category: categoryFilter,
            modificationFilter: modificationFilter,
            filenameRegex: filenameRegex,
            pathRegex: pathRegex
        )
    }

    func scheduleSearch() {
        searchTask?.cancel()
        let query = makeCurrentSearchQuery()
        let debounce = settings.debounceMilliseconds
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: debounce * 1_000_000)
            guard !Task.isCancelled, let self else { return }

            if !query.hasSearchCriteria {
                // An empty query is intentionally not a request to list the
                // whole database. Keep the window quiet while still updating
                // the sidebar counts in the background.
                self.results = []
                self.selectedResult = nil
                self.lastSearchMilliseconds = 0
                let counts = await self.searchEngine.facetCounts(query)
                guard !Task.isCancelled else { return }
                self.facetCounts = counts
                return
            }

            let startedAt = Date()
            let found = await self.searchEngine.search(query)
            guard !Task.isCancelled else { return }
            self.results = found
            self.lastSearchMilliseconds = Date().timeIntervalSince(startedAt) * 1_000

            if let selectedResult = self.selectedResult,
               found.contains(where: { $0.fullPath == selectedResult.fullPath }) {
                // Keep the current selection while the result set changes.
            } else {
                self.selectedResult = found.first
            }

            let counts = await self.searchEngine.facetCounts(query)
            guard !Task.isCancelled else { return }
            self.facetCounts = counts
        }
    }

    func applyAdvancedSearch(
        displayText: String,
        filenameRegex: String,
        pathRegex: String,
        extensionFilter: String,
        kindFilter: FileKindFilter
    ) {
        isApplyingAdvancedSearch = true
        advancedSearchActive = true
        searchText = displayText
        self.filenameRegex = filenameRegex
        self.pathRegex = pathRegex
        self.extensionFilter = extensionFilter
        self.kindFilter = kindFilter
        categoryFilter = .all
        modificationFilter = .any
        sort = .relevance
        isApplyingAdvancedSearch = false
        scheduleSearch()
    }

    func clearSearch() {
        isApplyingAdvancedSearch = true
        advancedSearchActive = false
        searchText = ""
        filenameRegex = ""
        pathRegex = ""
        extensionFilter = ""
        categoryFilter = .all
        kindFilter = .all
        modificationFilter = .any
        sort = .relevance
        isApplyingAdvancedSearch = false
        scheduleSearch()
    }

    func select(path: String?) {
        selectedResult = results.first { $0.fullPath == path }
    }

    func preview(_ record: FileRecord) {
        selectedResult = record
        quickLookPreview.show(record)
        markUsed(record)
    }

    func open(_ record: FileRecord) {
        selectedResult = record
        NSWorkspace.shared.open(URL(fileURLWithPath: record.fullPath))
        markUsed(record)
    }

    func reveal(_ record: FileRecord) {
        selectedResult = record
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: record.fullPath)])
        markUsed(record)
    }

    func copyFile(_ record: FileRecord) {
        selectedResult = record
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(fileURLWithPath: record.fullPath) as NSURL])
        markUsed(record)
        notice = NFSLocalized.copying(record.filename)
    }

    func copyPath(_ record: FileRecord) {
        selectedResult = record
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(record.fullPath, forType: .string)
        markUsed(record)
        notice = NFSLocalized.copiedPath
    }

    func requestMoveToTrash(_ record: FileRecord) {
        selectedResult = record
        pendingTrash = record
    }

    func moveToTrash(_ record: FileRecord) {
        pendingTrash = nil
        do {
            try FileManager.default.trashItem(
                at: URL(fileURLWithPath: record.fullPath),
                resultingItemURL: nil
            )
            Task { [weak self] in
                guard let self else { return }
                try? await self.database.deletePath(record.fullPath)
                await self.refreshStats()
                self.scheduleSearch()
            }
            notice = NFSLocalized.movedToTrash(record.filename)
        } catch {
            notice = NFSLocalized.unableToTrash(record.filename, error: error.localizedDescription)
            AppLogger.ui.error("Trash operation failed: \(String(describing: error), privacy: .public)")
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = NFSLocalized.text("选择要索引的文件夹", "Choose a folder to index")
        panel.message = NFSLocalized.text(
            "NativeFileSearch 将为此文件夹建立文件名和路径索引。",
            "NativeFileSearch will build a filename and path index for this folder."
        )
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in
                await self?.addLocation(url: url)
            }
        }
    }

    func completeInitialSetup() {
        settings.markInitialSetupCompleted()
        showOnboarding = false
    }

    func addLocation(url: URL, refreshUI: Bool = true) async {
        let path = url.standardizedFileURL.path
        guard FileManager.default.fileExists(atPath: path) else {
            notice = NFSLocalized.text("无法访问所选文件夹。", "The selected folder is unavailable.")
            return
        }

        do {
            try await database.addIndexedLocation(path: path)
            if refreshUI {
                await refreshLocations()
                await indexer.setIndexedLocations(indexedLocations)
                await restartWatcher()
                Task { [weak self] in
                    await self?.indexer.rebuild(path: path)
                    await self?.refreshStats()
                }
            }
        } catch {
            notice = NFSLocalized.text(
                "无法添加文件夹：\(error.localizedDescription)",
                "Could not add folder: \(error.localizedDescription)"
            )
            AppLogger.database.error("Cannot add indexed location: \(String(describing: error), privacy: .public)")
        }
    }

    func removeLocation(_ location: IndexedLocation) {
        Task { [weak self] in
            guard let self else { return }
            do {
                await self.indexer.prepareForLocationRemoval(path: location.path)
                try await self.database.removeIndexedLocation(path: location.path)
                await self.refreshLocations()
                await self.indexer.setIndexedLocations(self.indexedLocations)
                await self.restartWatcher()
                await self.refreshStats()
            } catch {
                self.notice = NFSLocalized.text(
                    "无法移除文件夹：\(error.localizedDescription)",
                    "Could not remove folder: \(error.localizedDescription)"
                )
                AppLogger.database.error("Cannot remove indexed location: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func setPaused(_ location: IndexedLocation, isPaused: Bool) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.database.setLocationPaused(path: location.path, isPaused: isPaused)
                await self.refreshLocations()
                await self.indexer.setIndexedLocations(self.indexedLocations)
                await self.restartWatcher()
            } catch {
                self.notice = NFSLocalized.text(
                    "无法更新索引状态：\(error.localizedDescription)",
                    "Could not update indexing status: \(error.localizedDescription)"
                )
            }
        }
    }

    func rebuild(_ location: IndexedLocation) {
        Task { [weak self] in
            guard let self else { return }
            await self.indexer.rebuild(path: location.path)
            await self.refreshLocations()
            await self.refreshStats()
        }
    }

    func rebuildAll() {
        Task { [weak self] in
            guard let self else { return }
            await self.indexer.indexAll()
            await self.refreshLocations()
            await self.refreshStats()
        }
    }

    func showSearchWindow() {
        // Treat every global-hotkey invocation as a fresh search session.
        // This keeps stale results from reappearing when the window is
        // dismissed and later opened again.
        isApplyingAdvancedSearch = true
        progressSearchTask?.cancel()
        progressSearchTask = nil
        advancedSearchActive = false
        searchText = ""
        extensionFilter = ""
        filenameRegex = ""
        pathRegex = ""
        categoryFilter = .all
        kindFilter = .all
        modificationFilter = .any
        sort = .relevance
        results = []
        selectedResult = nil
        lastSearchMilliseconds = 0
        isApplyingAdvancedSearch = false

        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            let window = NSApp.windows.first { $0.title == "NativeFileSearch" || $0.identifier?.rawValue == "search" }
                ?? NSApp.keyWindow
            window?.makeKeyAndOrderFront(nil)
            NotificationCenter.default.post(name: .nfsFocusSearchField, object: nil)
        }
    }

    private func markUsed(_ record: FileRecord) {
        Task { [weak self] in
            try? await self?.database.markUsed(path: record.fullPath)
        }
    }

    private func refreshLocations() async {
        indexedLocations = await database.indexedLocations()
    }

    private func refreshStats() async {
        stats = await database.stats()
    }

    private func restartWatcher() async {
        watcher?.stop()
        let paths = indexedLocations.filter { !$0.isPaused }.map(\.path)
        guard !paths.isEmpty else {
            watcher = nil
            return
        }

        let sinceEventID = await database.lastEventID()
        let indexer = self.indexer
        watcher = FileEventWatcher(paths: paths, sinceEventID: sinceEventID) { change in
            Task {
                await indexer.handle(change)
            }
        }
        watcher?.start()
    }

    private func apply(progress: IndexProgress) {
        indexingStatus.currentPath = progress.path
        indexingStatus.processedCount = progress.processedCount

        if let errorMessage = progress.errorMessage {
            indexingStatus.phase = .error
            indexingStatus.lastError = errorMessage
            notice = NFSLocalized.text(
                "部分文件无法索引，请检查权限和日志。",
                "Some files could not be indexed. Check permissions and logs."
            )
        } else {
            indexingStatus.phase = progress.isFinished ? .idle : .indexing
        }
        scheduleSearchForProgress(progress)
        if progress.isFinished {
            Task { [weak self] in
                await self?.refreshLocations()
                await self?.refreshStats()
            }
        }
    }

    private func scheduleSearchForProgress(_ progress: IndexProgress) {
        let queryHasCriteria = makeCurrentSearchQuery().hasSearchCriteria
        guard progress.isFinished || queryHasCriteria else { return }

        let now = Date()
        if progress.isFinished {
            progressSearchTask?.cancel()
            progressSearchTask = nil
            lastProgressSearchAt = now
            scheduleSearch()
            return
        }

        guard progressSearchTask == nil else { return }

        let elapsed = now.timeIntervalSince(lastProgressSearchAt)
        let delay = max(0.05, 0.5 - elapsed)
        progressSearchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.progressSearchTask = nil
            self.lastProgressSearchAt = Date()
            self.scheduleSearch()
        }
    }
}
