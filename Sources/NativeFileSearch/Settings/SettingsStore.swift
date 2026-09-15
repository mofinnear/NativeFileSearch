import Foundation
import Carbon.HIToolbox

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

/// The shortcut used to reveal the selected result in Finder.
///
/// It is intentionally separate from the shortcut used to open a file. The
/// default follows the macOS convention of using Command + Return for an
/// alternate action, while the stored values allow users to record another
/// combination from Settings.
enum FinderRevealShortcutConfiguration {
    static let keyCodeKey = "nfsRevealShortcutKeyCode"
    static let modifiersKey = "nfsRevealShortcutModifiers"
    static let displayKey = "nfsRevealShortcutDisplay"

    static let defaultKeyCode: UInt32 = 36 // Return
    static let defaultModifiers: UInt32 = UInt32(cmdKey)
    static let defaultDisplayName = "⌘ 回车"

    static var keyCode: UInt32 {
        let value = UserDefaults.standard.object(forKey: keyCodeKey) as? NSNumber
        return value.map { UInt32(max(0, $0.intValue)) } ?? defaultKeyCode
    }

    static var modifiers: UInt32 {
        let value = UserDefaults.standard.object(forKey: modifiersKey) as? NSNumber
        return value.map { UInt32(max(0, $0.intValue)) } ?? defaultModifiers
    }

    static var displayName: String {
        let value = UserDefaults.standard.string(forKey: displayKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value! : defaultDisplayName
    }

    static var hasCustomBinding: Bool {
        UserDefaults.standard.object(forKey: displayKey) != nil
    }

    static func save(keyCode: UInt32, modifiers: UInt32, displayName: String) {
        let defaults = UserDefaults.standard
        defaults.set(Int(keyCode), forKey: keyCodeKey)
        defaults.set(Int(modifiers), forKey: modifiersKey)
        defaults.set(displayName, forKey: displayKey)
    }

    static func reset() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: keyCodeKey)
        defaults.removeObject(forKey: modifiersKey)
        defaults.removeObject(forKey: displayKey)
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
