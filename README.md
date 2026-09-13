# NativeFileSearch

NativeFileSearch is a native macOS file-name and path search application inspired by Everything and Raycast. It deliberately keeps Spotlight out of the search path:

`FileManager scan → SQLite WAL index → FSEvents incremental updates → SQLite-only search`

Current release: `1.0`

The project is split into the following modules:

- `App`: application lifecycle, state coordination, and the configurable global hot key.
- `UI`: SwiftUI search window, result rows, onboarding, settings, and keyboard commands.
- `SearchEngine`: the actor façade that owns the query boundary; it delegates only to SQLite and never scans the file system.
- `Indexer`: initial scans, bounded batches, generation-based stale-row pruning, rebuilds, and incremental refreshes.
- `FileWatcher`: file-level FSEvents stream with dropped-event recovery.
- `Database`: SQLite schema, migrations, WAL configuration, indexes, and optional FTS5 trigram companion index.
- `Models` / `Settings` / `Utilities`: value types, preferences, metadata extraction, and logging.

## Current implementation status

- Phase 1: project structure, SQLite schema, WAL, indexes, FTS5 fallback, and database tests.
- Phase 2: initial directory selection, background FileManager scan, permission-tolerant metadata reads, and batch writes.
- Phase 3: name/path substring search, prefix/exact relevance, extension and kind filters, sort options, and debounce.
- Phase 4: minimal SwiftUI search window and Indexed Locations settings page.
- Phase 5: open, Finder reveal, copy URL, copy full path, double-click, context menu, and confirmed Move to Trash.
- Phase 6: FSEvents create/delete/rename/modify handling, coalescing, persisted event IDs, and local recovery scans for dropped/incomplete logs.
- Phase 7: built-in and user-defined global hot keys via Carbon `RegisterEventHotKey`.
- Phase 8: bounded batches, SQLite query limits, debounce, WAL, background actors, and a repeatable database smoke benchmark.

## Build

Open `NativeFileSearch.xcodeproj` in Xcode and run the `NativeFileSearch` scheme. The project is intentionally unsandboxed for the developer build so user-selected folders and external volumes can be indexed without security-scoped bookmark plumbing. A signed distribution build should either keep the explicit Full Disk Access guidance or add bookmark storage before enabling App Sandbox.

For a command-line build on a machine with a matching Xcode/SDK toolchain:

```sh
xcodebuild -project NativeFileSearch.xcodeproj -scheme NativeFileSearch -configuration Debug build
```

To package a standalone local application without Xcode:

```sh
./Packaging/build-app.sh
```

This creates `dist/NativeFileSearch.app` and `dist/NativeFileSearch-macOS.zip`. The local bundle uses an ad-hoc signature for development; a distributable build still needs Apple Developer signing and notarization.

The repository also contains `Package.swift` for source-level SwiftPM builds, the database test target, and `Tools/DatabaseSmoke.swift`, `Tools/DiskPersistenceSmoke.swift`, and `Tools/IndexerSmoke.swift` for runtime search/index smoke benchmarks. On a machine with only Command Line Tools, XCTest may be unavailable; run the smoke benchmarks instead of treating that toolchain limitation as an application failure.

The smoke benchmark can be compiled against the local sources with the following command:

```sh
clang -c -isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX26.4.sdk \
  -I Sources/SQLiteShim/include \
  Sources/SQLiteShim/sqlite_shim.c -o /tmp/nativefilesearch-sqlite-shim.o
swiftc -swift-version 5 -parse-as-library \
  -import-objc-header NativeFileSearch-Bridging-Header.h \
  -I Sources/SQLiteShim/include \
  -module-cache-path /tmp/nativefilesearch-modulecache \
  -Xcc -fmodules-cache-path=/tmp/nativefilesearch-clang-cache \
  Tools/DatabaseSmoke.swift \
  Sources/NativeFileSearch/Database/FileDatabase.swift \
  Sources/NativeFileSearch/Models/FileRecord.swift \
  Sources/NativeFileSearch/Utilities/AppLogger.swift \
  Sources/NativeFileSearch/Utilities/FileMetadata.swift \
  Sources/NativeFileSearch/Utilities/String+Search.swift \
  /tmp/nativefilesearch-sqlite-shim.o -lsqlite3 -o /tmp/nativefilesearch-db-smoke
/tmp/nativefilesearch-db-smoke
```

## Index design

The `files` table stores the requested fields plus normalized search columns, root ownership, scan generation, and recent-use time. `full_path` is unique. B-tree indexes cover normalized file name, normalized path, extension, modification date, size, and root/generation pruning. When the system SQLite exposes FTS5 trigram tokenization, `files_fts` accelerates substring lookup; otherwise the query falls back to indexed schema plus `instr` filtering.

Scanning is generation based: rows observed during a scan receive the current generation and only stale rows inside the affected root/subtree are removed after a successful scan. This avoids holding millions of `FileMetadata` values in memory and keeps a partial permission failure from deleting valid old rows.

## Permissions and diagnostics

Files that cannot be read are logged with the `com.nativefilesearch.app` categories `database`, `indexer`, `fsevents`, and `ui`, while the scan continues. The UI surfaces a non-fatal warning and suggests Full Disk Access for protected locations.

## Feedback

Please open a GitHub Issue for bug reports and feature requests. Include the macOS version, app version, steps to reproduce, and expected versus actual behavior. Remove private file names and paths from screenshots or logs before sharing them.
