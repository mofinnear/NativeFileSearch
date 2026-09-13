import Carbon.HIToolbox
import Foundation

private let nfsHotKeySignature: OSType = 0x4E465358 // "NFSX"

enum GlobalHotKeyPreset: String, CaseIterable, Identifiable, Sendable {
    case optionSpace = "option-space"
    case commandShiftSpace = "command-shift-space"
    case optionF = "option-f"
    case custom = "custom"

    var id: String { rawValue }

    var keyCode: UInt32 {
        switch self {
        case .optionSpace, .commandShiftSpace:
            return UInt32(kVK_Space)
        case .optionF:
            return UInt32(kVK_ANSI_F)
        case .custom:
            return GlobalHotKeyConfiguration.customBinding?.keyCode
                ?? GlobalHotKeyPreset.optionSpace.keyCode
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .optionSpace, .optionF:
            return UInt32(optionKey)
        case .commandShiftSpace:
            return UInt32(cmdKey | shiftKey)
        case .custom:
            return GlobalHotKeyConfiguration.customBinding?.modifiers
                ?? GlobalHotKeyPreset.optionSpace.modifiers
        }
    }

    var label: String {
        switch self {
        case .optionSpace:
            return NFSLocalized.text("⌥ 空格", "⌥ Space")
        case .commandShiftSpace:
            return NFSLocalized.text("⌘ ⇧ 空格", "⌘ ⇧ Space")
        case .optionF:
            return NFSLocalized.text("⌥ F", "⌥ F")
        case .custom:
            return GlobalHotKeyConfiguration.customBinding?.label
                ?? NFSLocalized.text("自定义（未设置）", "Custom (Not Set)")
        }
    }

    static var current: GlobalHotKeyPreset {
        guard let rawValue = UserDefaults.standard.string(forKey: "nfsHotKeyPreset"),
              let preset = GlobalHotKeyPreset(rawValue: rawValue) else {
            return .optionSpace
        }
        return preset
    }
}

struct GlobalHotKeyBinding: Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32
    let label: String
}

enum GlobalHotKeyConfiguration {
    static let customKeyCodeKey = "nfsHotKeyCustomKeyCode"
    static let customModifiersKey = "nfsHotKeyCustomModifiers"
    static let customDisplayKey = "nfsHotKeyCustomDisplay"

    static var customBinding: GlobalHotKeyBinding? {
        let defaults = UserDefaults.standard
        let keyCode = defaults.integer(forKey: customKeyCodeKey)
        let modifiers = defaults.integer(forKey: customModifiersKey)
        guard keyCode >= 0, modifiers > 0 else { return nil }

        let storedLabel = defaults.string(forKey: customDisplayKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let label = storedLabel?.isEmpty == false
            ? storedLabel!
            : NFSLocalized.text("自定义快捷键", "Custom Shortcut")

        return GlobalHotKeyBinding(
            keyCode: UInt32(keyCode),
            modifiers: UInt32(modifiers),
            label: label
        )
    }

    static var currentBinding: GlobalHotKeyBinding {
        let preset = GlobalHotKeyPreset.current
        if preset == .custom {
            return customBinding ?? GlobalHotKeyPreset.optionSpace.builtInBinding
        }
        return preset.builtInBinding
    }

    static func saveCustomBinding(
        keyCode: UInt32,
        modifiers: UInt32,
        label: String
    ) {
        let defaults = UserDefaults.standard
        defaults.set(Int(keyCode), forKey: customKeyCodeKey)
        defaults.set(Int(modifiers), forKey: customModifiersKey)
        defaults.set(label, forKey: customDisplayKey)
        defaults.set(GlobalHotKeyPreset.custom.rawValue, forKey: "nfsHotKeyPreset")
    }

    static func clearCustomBinding() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: customKeyCodeKey)
        defaults.removeObject(forKey: customModifiersKey)
        defaults.removeObject(forKey: customDisplayKey)
    }
}

private extension GlobalHotKeyPreset {
    var builtInBinding: GlobalHotKeyBinding {
        switch self {
        case .optionSpace:
            return GlobalHotKeyBinding(
                keyCode: UInt32(kVK_Space),
                modifiers: UInt32(optionKey),
                label: NFSLocalized.text("⌥ 空格", "⌥ Space")
            )
        case .commandShiftSpace:
            return GlobalHotKeyBinding(
                keyCode: UInt32(kVK_Space),
                modifiers: UInt32(cmdKey | shiftKey),
                label: NFSLocalized.text("⌘ ⇧ 空格", "⌘ ⇧ Space")
            )
        case .optionF:
            return GlobalHotKeyBinding(
                keyCode: UInt32(kVK_ANSI_F),
                modifiers: UInt32(optionKey),
                label: NFSLocalized.text("⌥ F", "⌥ F")
            )
        case .custom:
            return GlobalHotKeyConfiguration.customBinding
                ?? GlobalHotKeyPreset.optionSpace.builtInBinding
        }
    }
}

private func nfsGlobalHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    NotificationCenter.default.post(name: .nfsShowSearchWindow, object: nil)
    return noErr
}

final class GlobalHotKeyManager {
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?
    private var configurationObserver: NSObjectProtocol?

    init() {
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .nfsHotKeyConfigurationChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restart()
        }
    }

    func start() {
        guard hotKeyReference == nil else { return }
        let defaults = UserDefaults.standard
        let isEnabled = defaults.object(forKey: "nfsHotKeyEnabled") as? Bool ?? true
        guard isEnabled else {
            AppLogger.ui.info("Global search hot key is disabled")
            return
        }

        let binding = GlobalHotKeyConfiguration.currentBinding

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerResult = InstallEventHandler(
            GetApplicationEventTarget(),
            nfsGlobalHotKeyHandler,
            1,
            &eventType,
            nil,
            &eventHandlerReference
        )

        guard handlerResult == noErr else {
            AppLogger.ui.error("Cannot install global hot key handler: \(handlerResult)")
            return
        }

        let hotKeyID = EventHotKeyID(signature: nfsHotKeySignature, id: 1)
        let registerResult = RegisterEventHotKey(
            binding.keyCode,
            binding.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )

        guard registerResult == noErr else {
            AppLogger.ui.error("Cannot register global search hot key: \(registerResult)")
            RemoveEventHandler(eventHandlerReference)
            eventHandlerReference = nil
            return
        }

        AppLogger.ui.info("Global search hot key registered: \(binding.label)")
    }

    func restart() {
        stopRegistration()
        start()
    }

    func stop() {
        stopRegistration()
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
    }

    private func stopRegistration() {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
            self.hotKeyReference = nil
        }
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
            self.eventHandlerReference = nil
        }
    }

    deinit {
        stop()
    }
}
