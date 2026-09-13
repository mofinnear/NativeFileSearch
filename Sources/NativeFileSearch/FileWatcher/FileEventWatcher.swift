import CoreServices
import Foundation

struct FileSystemChange: Sendable {
    let path: String
    let flags: UInt32
    let eventID: UInt64
}

final class FileEventWatcher {
    typealias ChangeHandler = @Sendable (FileSystemChange) -> Void

    private let paths: [String]
    private let sinceEventID: UInt64
    private let handler: ChangeHandler
    private let eventQueue = DispatchQueue(label: "com.nativefilesearch.fsevents", qos: .utility)
    private let queueKey = DispatchSpecificKey<Void>()
    private var stream: FSEventStreamRef?

    init(paths: [String], sinceEventID: UInt64, handler: @escaping ChangeHandler) {
        self.paths = paths
        self.sinceEventID = sinceEventID == 0
            ? UInt64(kFSEventStreamEventIdSinceNow)
            : sinceEventID
        self.handler = handler
        eventQueue.setSpecific(key: queueKey, value: ())
    }

    func start() {
        eventQueue.async { [weak self] in
            self?.startOnQueue()
        }
    }

    func stop() {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            stopOnQueue()
        } else {
            eventQueue.sync {
                self.stopOnQueue()
            }
        }
    }

    deinit {
        stop()
    }

    private func startOnQueue() {
        guard stream == nil, !paths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let createFlags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagIgnoreSelf
                | kFSEventStreamCreateFlagWatchRoot
                | kFSEventStreamCreateFlagNoDefer
        )

        guard let eventStream = FSEventStreamCreate(
            nil,
            Self.eventCallback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(sinceEventID),
            0.15,
            createFlags
        ) else {
            AppLogger.watcher.error("FSEventStreamCreate failed")
            return
        }

        FSEventStreamSetDispatchQueue(eventStream, eventQueue)
        guard FSEventStreamStart(eventStream) else {
            AppLogger.watcher.error("FSEventStreamStart failed")
            FSEventStreamInvalidate(eventStream)
            FSEventStreamRelease(eventStream)
            return
        }

        stream = eventStream
        AppLogger.watcher.info("FSEvents watcher started for \(self.paths.count) root(s)")
    }

    private func stopOnQueue() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamSetDispatchQueue(stream, nil)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        AppLogger.watcher.info("FSEvents watcher stopped")
    }

    private static let eventCallback: FSEventStreamCallback = {
        _, clientCallBackInfo, numberOfEvents, rawEventPaths, eventFlags, eventIDs in
        guard let clientCallBackInfo else { return }

        let watcher = Unmanaged<FileEventWatcher>
            .fromOpaque(clientCallBackInfo)
            .takeUnretainedValue()
        let eventPaths = rawEventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)

        for index in 0..<numberOfEvents {
            let eventPath = eventPaths[index]
            watcher.handler(
                FileSystemChange(
                    path: String(cString: eventPath),
                    flags: UInt32(eventFlags[index]),
                    eventID: UInt64(eventIDs[index])
                )
            )
        }
    }
}
