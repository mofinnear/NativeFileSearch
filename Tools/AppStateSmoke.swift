import Foundation

@main
struct AppStateSmoke {
    static func main() async throws {
        let resultCount = try await runSmoke()
        guard resultCount > 0 else {
            throw SmokeFailure(message: "AppState search returned no results for an indexed term")
        }
        print("NativeFileSearch AppState smoke passed: \(resultCount) results")
    }

    @MainActor
    private static func runSmoke() async throws -> Int {
        let state = AppState()
        state.searchText = "swift"
        try await Task.sleep(nanoseconds: 500_000_000)
        let directResults = await state.searchEngine.search(
            SearchQuery(text: "swift", extensionFilter: "", kind: .all, sort: .relevance)
        )
        if state.results.isEmpty {
            let stats = await state.database.stats()
            let isReady = await state.database.isReady
            let startupError = await state.database.startupError ?? "none"
            throw SmokeFailure(
                message: "AppState results=0, direct results=\(directResults.count), stats=\(stats.fileCount)/\(stats.folderCount), ready=\(isReady), error=\(startupError), db=\(SettingsStore.shared.databaseURL().path)"
            )
        }
        return state.results.count
    }
}

private struct SmokeFailure: Error, LocalizedError {
    let message: String

    var errorDescription: String? { message }
}
