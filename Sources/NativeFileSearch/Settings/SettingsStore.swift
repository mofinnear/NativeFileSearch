import Foundation

enum OpenFileShortcut: String, CaseIterable, Identifiable, Sendable {
    case returnKey = "return"
    case commandO = "commandO"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .returnKey:
            return NFSLocalized.text("回车", "Return")
        case .commandO:
            return "Command + O"
        }
    }

    var keyHint: String {
        switch self {
        case .returnKey: return "↵"
        case .commandO: return "⌘O"
        }
    }
}

final class SettingsStore {
    static let shared = SettingsStore()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var debounceMilliseconds: UInt64 {
        let value = defaults.object(forKey: "searchDebounceMilliseconds") as? NSNumber
        return UInt64(max(30, min(value?.intValue ?? 60, 80)))
    }

    var hasCompletedInitialSetup: Bool {
        defaults.bool(forKey: "nfsInitialSetupCompleted")
    }

    func markInitialSetupCompleted() {
        defaults.set(true, forKey: "nfsInitialSetupCompleted")
    }

    func databaseURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("NativeFileSearch", isDirectory: true)
            .appendingPathComponent("index.sqlite", isDirectory: false)
    }
}
