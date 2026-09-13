// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NativeFileSearch",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "NativeFileSearch", targets: ["NativeFileSearch"])
    ],
    targets: [
        .target(
            name: "SQLiteShim",
            path: "Sources/SQLiteShim",
            sources: ["sqlite_shim.c"],
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "NativeFileSearch",
            dependencies: ["SQLiteShim"],
            path: "Sources/NativeFileSearch",
            sources: [
                "App/AppDelegate.swift",
                "App/AppState.swift",
                "App/GlobalHotKeyManager.swift",
                "App/NativeFileSearchApp.swift",
                "App/Notifications.swift",
                "Database/FileDatabase.swift",
                "FileWatcher/FileEventWatcher.swift",
                "Indexer/FileIndexer.swift",
                "Models/FileRecord.swift",
                "SearchEngine/SearchEngine.swift",
                "Settings/AppLanguage.swift",
                "Settings/SettingsStore.swift",
                "UI/FileIconView.swift",
                "UI/AdvancedSearchView.swift",
                "UI/KeyboardCommandMonitor.swift",
                "UI/OnboardingView.swift",
                "UI/QuickLookPreviewController.swift",
                "UI/SearchWindowView.swift",
                "UI/SettingsView.swift",
                "Utilities/AppLogger.swift",
                "Utilities/FileMetadata.swift",
                "Utilities/String+Search.swift"
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreServices"),
                .linkedFramework("QuickLookUI"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        ),
        .testTarget(
            name: "NativeFileSearchTests",
            dependencies: ["NativeFileSearch"],
            path: "Tests/NativeFileSearchTests",
            sources: ["FileDatabaseTests.swift"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
