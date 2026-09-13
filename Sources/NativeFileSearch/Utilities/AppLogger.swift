import OSLog

enum AppLogger {
    static let subsystem = "com.nativefilesearch.app"

    static let database = Logger(subsystem: subsystem, category: "database")
    static let indexer = Logger(subsystem: subsystem, category: "indexer")
    static let watcher = Logger(subsystem: subsystem, category: "fsevents")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
