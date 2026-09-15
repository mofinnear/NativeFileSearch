import Foundation

struct IndexProgress: Sendable {
    let path: String?
    let processedCount: Int
    let isFinished: Bool
    let errorMessage: String?
}

extension Notification.Name {
    static let nfsIndexProgress = Notification.Name("NativeFileSearch.indexProgress")
}

actor FileIndexer {
    private let database: FileDatabase
    private let fileManager = FileManager.default
    private let batchSize = 750

    private var roots: [IndexedLocation] = []
    private var pendingChanges: [String: FileSystemChange] = [:]
    private var flushTask: Task<Void, Never>?
    private var isScanning = false

    init(database: FileDatabase) {
        self.database = database
    }

    func setIndexedLocations(_ locations: [IndexedLocation]) {
        roots = locations
    }

    /// Stops new events for a location and waits for a scan already in
    /// progress to finish before the database removes that location. This
    /// prevents a late scan batch from recreating rows after removal.
    func prepareForLocationRemoval(path: String) async {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        roots.removeAll { $0.path == normalizedPath }
        pendingChanges = pendingChanges.filter { !isPath($0.key, inside: normalizedPath) }

        while isScanning {
            do {
                try await Task.sleep(nanoseconds: 50_000_000)
            } catch {
                return
            }
        }

        pendingChanges = pendingChanges.filter { !isPath($0.key, inside: normalizedPath) }
        if pendingChanges.isEmpty {
            flushTask?.cancel()
            flushTask = nil
        }
    }

    func indexAll() async {
        guard !isScanning else { return }
        isScanning = true
        defer {
            isScanning = false
            if !pendingChanges.isEmpty {
                schedulePendingFlush()
            }
        }

        for location in roots where !location.isPaused {
            await scan(path: location.path, rootPath: location.path, pruneUnseen: true)
        }
    }

    func rebuild(path: String) async {
        guard !isScanning else { return }
        guard let location = matchingRoot(for: path), !location.isPaused else { return }

        isScanning = true
        defer {
            isScanning = false
            if !pendingChanges.isEmpty {
                schedulePendingFlush()
            }
        }
        await scan(path: path, rootPath: location.path, pruneUnseen: true)
    }

    func handle(_ change: FileSystemChange) {
        let recoveryFlags = UInt32(kFSEventStreamEventFlagRootChanged)
            | UInt32(kFSEventStreamEventFlagMustScanSubDirs)
            | UInt32(kFSEventStreamEventFlagUserDropped)
            | UInt32(kFSEventStreamEventFlagKernelDropped)
            | UInt32(kFSEventStreamEventFlagEventIdsWrapped)
        let affectsConfiguredRoot = roots.contains { location in
            !location.isPaused
                && (isPath(change.path, inside: location.path)
                    || isPath(location.path, inside: change.path))
        }
        guard matchingRoot(for: change.path) != nil
            || change.path == "/"
            || (change.flags & recoveryFlags != 0 && affectsConfiguredRoot) else {
            return
        }

        if let existing = pendingChanges[change.path] {
            pendingChanges[change.path] = FileSystemChange(
                path: change.path,
                flags: existing.flags | change.flags,
                eventID: max(existing.eventID, change.eventID)
            )
        } else {
            pendingChanges[change.path] = change
        }

        schedulePendingFlush()
    }

    private func flushPendingChanges() async {
        flushTask = nil
        guard !isScanning else {
            schedulePendingFlush()
            return
        }

        isScanning = true
        defer {
            isScanning = false
            if !pendingChanges.isEmpty {
                schedulePendingFlush()
            }
        }

        let changes = pendingChanges.values.sorted { $0.path < $1.path }
        pendingChanges.removeAll(keepingCapacity: true)

        var latestEventID: UInt64 = 0
        for change in changes {
            latestEventID = max(latestEventID, change.eventID)
            await process(change)
        }

        if latestEventID > 0 {
            do {
                try await database.saveLastEventID(latestEventID)
            } catch {
                AppLogger.watcher.error("Cannot persist FSEvents ID: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func process(_ change: FileSystemChange) async {
        let rootChangedFlag = UInt32(kFSEventStreamEventFlagRootChanged)
        if change.flags & rootChangedFlag != 0 {
            let affectedLocations = roots.filter { location in
                guard !location.isPaused else { return false }
                return change.path == "/"
                    || isPath(change.path, inside: location.path)
                    || isPath(location.path, inside: change.path)
            }

            for location in affectedLocations {
                let available = fileManager.fileExists(atPath: location.path)
                await setLocationOffline(location, isOffline: !available)
                if available {
                    // A watch-root event can be delivered for the parent of
                    // an external volume. Re-scan the configured root so a
                    // reappearing volume is complete again.
                    await scan(path: location.path, rootPath: location.path, pruneUnseen: true)
                } else {
                    report(
                        path: location.path,
                        processedCount: 0,
                        finished: true,
                        error: PathUnavailableError(path: location.path)
                    )
                }
            }
            return
        }

        let lossFlags = UInt32(kFSEventStreamEventFlagMustScanSubDirs)
            | UInt32(kFSEventStreamEventFlagUserDropped)
            | UInt32(kFSEventStreamEventFlagKernelDropped)
            | UInt32(kFSEventStreamEventFlagEventIdsWrapped)

        if change.flags & lossFlags != 0 {
            let locations: [IndexedLocation]
            if change.path == "/" {
                locations = roots.filter { !$0.isPaused }
            } else if let location = matchingRoot(for: change.path), !location.isPaused {
                locations = [location]
            } else {
                locations = []
            }

            for location in locations {
                let candidate = change.path != "/"
                    && isPath(change.path, inside: location.path)
                    ? change.path
                    : location.path
                let scanPath = directoryOrParentPath(candidate, fallback: location.path)
                await scan(path: scanPath, rootPath: location.path, pruneUnseen: true)
            }
            return
        }

        guard let location = matchingRoot(for: change.path), !location.isPaused else { return }

        let exists = fileManager.fileExists(atPath: change.path)
        if !exists {
            if change.path == location.path {
                await setLocationOffline(location, isOffline: true)
                report(
                    path: location.path,
                    processedCount: 0,
                    finished: true,
                    error: PathUnavailableError(path: location.path)
                )
                return
            }

            // A rename is delivered as a path event. If the old path is gone,
            // removing its subtree also handles directory moves cleanly.
            do {
                try await database.deletePath(change.path)
            } catch {
                report(path: change.path, processedCount: 0, finished: false, error: error)
            }
            return
        }

        var isDirectoryValue = ObjCBool(false)
        _ = fileManager.fileExists(atPath: change.path, isDirectory: &isDirectoryValue)
        let isDirectory = isDirectoryValue.boolValue
        if isDirectory || change.flags == 0 {
            await scan(path: change.path, rootPath: location.path, pruneUnseen: true)
        } else {
            await refreshFile(path: change.path, rootPath: location.path)
        }
    }

    private func refreshFile(path: String, rootPath: String) async {
        do {
            let generation = try await database.beginGeneration()
            let metadata = try FileMetadata(url: URL(fileURLWithPath: path), rootPath: rootPath)
            try await database.upsert([metadata], generation: generation)
            report(path: path, processedCount: 1, finished: true, error: nil)
        } catch FileMetadata.MetadataError.symbolicLink {
            return
        } catch {
            report(path: path, processedCount: 0, finished: false, error: error)
        }
    }

    private func scan(path: String, rootPath: String, pruneUnseen: Bool) async {
        // Publish the in-progress state before touching the filesystem so the
        // UI can explain that an empty or partial result set is temporary.
        report(path: path, processedCount: 0, finished: false, error: nil)

        guard fileManager.fileExists(atPath: path) else {
            if path == rootPath,
               let location = roots.first(where: { $0.path == rootPath }) {
                await setLocationOffline(location, isOffline: true)
            }
            let error = PathUnavailableError(path: path)
            AppLogger.indexer.warning("Indexed path is unavailable; keeping existing rows: \(path, privacy: .private)")
            report(path: path, processedCount: 0, finished: true, error: error)
            return
        }

        let url = URL(fileURLWithPath: path).standardizedFileURL
        let generation: Int64
        do {
            generation = try await database.beginGeneration()
        } catch {
            report(path: path, processedCount: 0, finished: false, error: error)
            return
        }

        report(path: path, processedCount: 0, finished: false, error: nil)

        var processed = 0
        var metadataErrors = 0
        var batch: [FileMetadata] = []
        batch.reserveCapacity(batchSize)
        let enumerationIssues = ScanIssueCounter()
        let propertyKeys: Set<URLResourceKey> = [
            .nameKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]

        func flushBatch() async throws {
            guard !batch.isEmpty else { return }
            try await database.upsert(batch, generation: generation)
            processed += batch.count
            batch.removeAll(keepingCapacity: true)
            report(path: path, processedCount: processed, finished: false, error: nil)
        }

        do {
            do {
                let rootMetadata = try FileMetadata(url: url, rootPath: rootPath)
                batch.append(rootMetadata)
            } catch FileMetadata.MetadataError.symbolicLink {
                metadataErrors += 1
            } catch {
                metadataErrors += 1
                AppLogger.indexer.warning("Cannot read indexed root metadata for \(path, privacy: .private): \(String(describing: error), privacy: .public)")
            }

            if let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: Array(propertyKeys),
                options: [],
                errorHandler: { failedURL, error in
                    enumerationIssues.increment()
                    AppLogger.indexer.warning(
                        "Cannot enumerate \(failedURL.path, privacy: .private): \(String(describing: error), privacy: .public)"
                    )
                    return true
                }
            ) {
                while let childURL = enumerator.nextObject() as? URL {
                    if Task.isCancelled { return }

                    let values: URLResourceValues
                    do {
                        values = try childURL.resourceValues(forKeys: propertyKeys)
                    } catch {
                        metadataErrors += 1
                        AppLogger.indexer.warning(
                            "Cannot read file metadata for \(childURL.path, privacy: .private): \(String(describing: error), privacy: .public)"
                        )
                        continue
                    }

                    if values.isSymbolicLink == true {
                        if values.isDirectory == true {
                            enumerator.skipDescendants()
                        }
                        continue
                    }

                    do {
                        batch.append(
                            try FileMetadata(
                                url: childURL,
                                rootPath: rootPath,
                                resourceValues: values
                            )
                        )
                        if batch.count >= batchSize {
                            try await flushBatch()
                        }
                    } catch FileMetadata.MetadataError.symbolicLink {
                        enumerator.skipDescendants()
                    } catch {
                        metadataErrors += 1
                        AppLogger.indexer.warning("Cannot read file metadata for \(childURL.path, privacy: .private): \(String(describing: error), privacy: .public)")
                    }
                }
                metadataErrors += enumerationIssues.count
            } else {
                metadataErrors += 1
                AppLogger.indexer.error("Cannot enumerate indexed path \(path, privacy: .private)")
            }

            try await flushBatch()

            if pruneUnseen && metadataErrors == 0 {
                try await database.removeUnseen(path: path, rootPath: rootPath, generation: generation)
            } else if metadataErrors > 0 {
                AppLogger.indexer.warning("Keeping stale rows below \(path, privacy: .private) because \(metadataErrors) metadata reads failed")
            }

            try await database.finishScan(rootPath: rootPath, scanDate: Date())
            let scanError: Error? = metadataErrors > 0
                ? MetadataReadErrors(count: metadataErrors, path: path)
                : nil
            report(path: path, processedCount: processed, finished: true, error: scanError)
        } catch {
            report(path: path, processedCount: processed, finished: false, error: error)
        }
    }

    private func matchingRoot(for path: String) -> IndexedLocation? {
        roots
            .filter { !$0.isPaused && isPath(path, inside: $0.path) }
            .max { $0.path.count < $1.path.count }
    }

    private func setLocationOffline(_ location: IndexedLocation, isOffline: Bool) async {
        if let index = roots.firstIndex(where: { $0.path == location.path }) {
            roots[index].isOffline = isOffline
        }
        do {
            try await database.setLocationOffline(path: location.path, isOffline: isOffline)
        } catch {
            AppLogger.database.error(
                "Cannot update offline state for \(location.path, privacy: .private): \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func isPath(_ path: String, inside root: String) -> Bool {
        if root == "/" { return path.hasPrefix("/") }
        return path == root || path.hasPrefix(root + "/")
    }

    private func directoryOrParentPath(_ path: String, fallback: String) -> String {
        let url = URL(fileURLWithPath: path)
        if let isDirectory = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDirectory == true {
            return path
        }
        let parent = url.deletingLastPathComponent().path
        return parent.isEmpty ? fallback : parent
    }

    private func report(path: String?, processedCount: Int, finished: Bool, error: Error?) {
        let message = error.map { String(describing: $0) }
        NotificationCenter.default.post(
            name: .nfsIndexProgress,
            object: IndexProgress(
                path: path,
                processedCount: processedCount,
                isFinished: finished,
                errorMessage: message
            )
        )
    }

    private func schedulePendingFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 120_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.flushPendingChanges()
        }
    }
}

private struct PathUnavailableError: LocalizedError {
    let path: String

    var errorDescription: String? {
        "Indexed path is unavailable: \(path)"
    }
}

private struct MetadataReadErrors: LocalizedError {
    let count: Int
    let path: String

    var errorDescription: String? {
        "\(count) entries could not be read below \(path)"
    }
}

private final class ScanIssueCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }
}
