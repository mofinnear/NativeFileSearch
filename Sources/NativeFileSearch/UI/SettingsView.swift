import AppKit
import Carbon.HIToolbox
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var locationToRemove: IndexedLocation?
    @AppStorage("nfsLanguage") private var languageRaw = AppLanguage.simplifiedChinese.rawValue
    @AppStorage("nfsHotKeyEnabled") private var hotKeyEnabled = true
    @AppStorage("nfsHotKeyPreset") private var hotKeyPresetRaw = GlobalHotKeyPreset.optionSpace.rawValue
    @AppStorage(GlobalHotKeyConfiguration.customKeyCodeKey) private var customHotKeyKeyCode = 0
    @AppStorage(GlobalHotKeyConfiguration.customModifiersKey) private var customHotKeyModifiers = 0
    @AppStorage(GlobalHotKeyConfiguration.customDisplayKey) private var customHotKeyDisplay = ""
    @AppStorage("nfsOpenFileShortcut") private var openFileShortcutRaw = OpenFileShortcut.returnKey.rawValue
    @AppStorage(FinderRevealShortcutConfiguration.keyCodeKey)
    private var revealShortcutKeyCode = Int(FinderRevealShortcutConfiguration.defaultKeyCode)
    @AppStorage(FinderRevealShortcutConfiguration.modifiersKey)
    private var revealShortcutModifiers = Int(FinderRevealShortcutConfiguration.defaultModifiers)
    @AppStorage(FinderRevealShortcutConfiguration.displayKey)
    private var revealShortcutDisplay = ""
    @State private var isRecordingCustomHotKey = false
    @State private var isRecordingRevealShortcut = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(NFSLocalized.text("设置", "Settings"))
                    .font(.title2.weight(.semibold))
                Spacer()
                Picker(NFSLocalized.text("语言", "Language"), selection: $languageRaw) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.label).tag(language.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
            }
            .padding(.bottom, 16)

            Divider()
                .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 10) {
                Text(NFSLocalized.text("唤醒与常驻", "Wake & Menu Bar"))
                    .font(.title2.weight(.semibold))

                HStack(spacing: 12) {
                    Image(systemName: "keyboard")
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 22)
                    Toggle(
                        NFSLocalized.text("启用全局快捷键", "Enable global shortcut"),
                        isOn: $hotKeyEnabled
                    )
                    Spacer()
                    Picker(NFSLocalized.text("唤醒快捷键", "Wake shortcut"), selection: $hotKeyPresetRaw) {
                        ForEach(GlobalHotKeyPreset.allCases) { preset in
                            Text(preset.label).tag(preset.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                    .disabled(!hotKeyEnabled)
                }

                HStack(spacing: 12) {
                    Image(systemName: "pencil.and.outline")
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 22)
                    Text(NFSLocalized.text("自定义快捷键", "Custom shortcut"))
                    Spacer()
                    Button {
                        guard hotKeyEnabled else { return }
                        isRecordingCustomHotKey.toggle()
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: isRecordingCustomHotKey ? "record.circle" : "keyboard")
                            Text(
                                isRecordingCustomHotKey
                                    ? NFSLocalized.text("取消录制", "Cancel recording")
                                    : customHotKeyLabel
                            )
                                .lineLimit(1)
                        }
                        .frame(minWidth: 190)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hotKeyEnabled)

                    if hasCustomHotKey {
                        Button {
                            clearCustomHotKey()
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .help(NFSLocalized.text("清除自定义快捷键", "Clear custom shortcut"))
                    }

                    GlobalHotKeyCaptureView(
                        isRecording: $isRecordingCustomHotKey,
                        onCapture: saveCustomHotKey,
                        onCancel: { isRecordingCustomHotKey = false }
                    )
                    .frame(width: 1, height: 1)
                }

                Text(NFSLocalized.text(
                    "关闭搜索窗口后，应用仍会安静地驻留在菜单栏；点击菜单栏放大镜或使用快捷键即可再次唤醒。点击上面的自定义框后，按下任意包含修饰键的组合键即可保存。",
                    "After the search window closes, the app stays quietly in the menu bar. Click the magnifying glass or use the shortcut to wake it. Click the custom field above, then press any combination that includes a modifier key."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 18)

            VStack(alignment: .leading, spacing: 10) {
                Text(NFSLocalized.text("打开文件快捷键", "Open File Shortcut"))
                    .font(.title2.weight(.semibold))

                HStack(spacing: 12) {
                    Image(systemName: "arrow.turn.down.left")
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 22)
                    Text(NFSLocalized.text("打开选中的文件", "Open selected file"))
                    Spacer()
                    Picker("", selection: $openFileShortcutRaw) {
                        ForEach(OpenFileShortcut.allCases) { shortcut in
                            Text(shortcut.label).tag(shortcut.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }

                Text(NFSLocalized.text(
                    "可选择回车，或使用更符合 macOS 习惯的 Command + O。",
                    "Choose Return, or Command + O for a more macOS-style shortcut."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 18)

            VStack(alignment: .leading, spacing: 10) {
                Text(NFSLocalized.text("Finder 显示快捷键", "Finder Reveal Shortcut"))
                    .font(.title2.weight(.semibold))

                HStack(spacing: 12) {
                    Image(systemName: "folder.badge.magnifyingglass")
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 22)
                    Text(NFSLocalized.text("在 Finder 中显示选中项目", "Reveal selected item in Finder"))
                    Spacer()
                    Button {
                        isRecordingRevealShortcut.toggle()
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: isRecordingRevealShortcut ? "record.circle" : "keyboard")
                            Text(
                                isRecordingRevealShortcut
                                    ? NFSLocalized.text("取消录制", "Cancel recording")
                                    : revealShortcutLabel
                            )
                                .lineLimit(1)
                        }
                        .frame(minWidth: 190)
                    }
                    .buttonStyle(.bordered)

                    if FinderRevealShortcutConfiguration.hasCustomBinding {
                        Button {
                            resetRevealShortcut()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.borderless)
                        .help(NFSLocalized.text("恢复为 ⌘ 回车", "Reset to Command + Return"))
                    }

                    GlobalHotKeyCaptureView(
                        isRecording: $isRecordingRevealShortcut,
                        onCapture: saveRevealShortcut,
                        onCancel: { isRecordingRevealShortcut = false }
                    )
                    .frame(width: 1, height: 1)
                }

                Text(NFSLocalized.text(
                    "默认使用 Command + 回车。选中搜索结果后按下该快捷键，Finder 会打开所在目录并选中该项目；点击右侧按钮即可录制其他组合键。",
                    "The default is Command + Return. With a result selected, it opens the containing folder in Finder and selects the item. Click the button to record another key combination."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 18)

            HStack {
                Text(NFSLocalized.text("索引位置", "Indexed Locations"))
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    appState.chooseFolder()
                } label: {
                    Label(NFSLocalized.text("添加文件夹", "Add Folder"), systemImage: "plus")
                }
            }
            .padding(.bottom, 12)

            List {
                if appState.indexedLocations.isEmpty {
                    Text(NFSLocalized.text("尚未添加索引位置", "No indexed locations yet"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.indexedLocations) { location in
                        IndexedLocationRow(location: location) {
                            appState.setPaused(location, isPaused: !location.isPaused)
                        } onRebuild: {
                            appState.rebuild(location)
                        } onRemove: {
                            locationToRemove = location
                        }
                    }
                }
            }
            .listStyle(.inset)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(NFSLocalized.text("索引状态", "Index Status"))
                    .font(.headline)
                HStack {
                    metric(NFSLocalized.text("文件", "Files"), value: appState.stats.fileCount.formatted())
                    metric(NFSLocalized.text("文件夹", "Folders"), value: appState.stats.folderCount.formatted())
                    metric(NFSLocalized.text("数据库", "Database"), value: formattedBytes(appState.stats.databaseSize))
                }
                if let lastIndexDate = appState.indexedLocations.compactMap(\.lastScanDate).max() {
                    Text(NFSLocalized.text(
                        "最近索引：\(lastIndexDate.formatted(date: .abbreviated, time: .shortened))",
                        "Last indexed: \(lastIndexDate.formatted(date: .abbreviated, time: .shortened))"
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(NFSLocalized.text("最近索引：从未", "Last indexed: Never"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if appState.indexingStatus.phase == .indexing,
                   let currentPath = appState.indexingStatus.currentPath {
                    Text(NFSLocalized.indexingLocation(
                        currentPath,
                        count: appState.indexingStatus.processedCount.formatted()
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if appState.indexingStatus.phase == .error,
                   let error = appState.indexingStatus.lastError {
                    Label(NFSLocalized.indexingWarning(error), systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 14)

            HStack {
                Text(NFSLocalized.text(
                    "NativeFileSearch 使用 SQLite 与 FSEvents 建立本地索引，搜索不依赖 Spotlight。",
                    "NativeFileSearch builds a local index with SQLite and FSEvents. Search does not depend on Spotlight."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                Button(NFSLocalized.text("重建全部", "Rebuild All")) {
                    appState.rebuildAll()
                }
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 620)
        .onChange(of: hotKeyEnabled) { _ in
            if !hotKeyEnabled {
                isRecordingCustomHotKey = false
            }
            NotificationCenter.default.post(name: .nfsHotKeyConfigurationChanged, object: nil)
        }
        .onChange(of: hotKeyPresetRaw) { _ in
            NotificationCenter.default.post(name: .nfsHotKeyConfigurationChanged, object: nil)
        }
        .onDisappear {
            isRecordingCustomHotKey = false
            isRecordingRevealShortcut = false
        }
        .onChange(of: languageRaw) { _ in
            NotificationCenter.default.post(name: .nfsLanguageChanged, object: nil)
        }
        .alert(item: $locationToRemove) { location in
            Alert(
                title: Text(NFSLocalized.text("移除索引位置？", "Remove indexed location?")),
                message: Text(NFSLocalized.text(
                    "此文件夹将停止监听，相关索引记录也会被删除。\n\n\(location.path)",
                    "This folder will stop being watched and its index records will be deleted.\n\n\(location.path)"
                )),
                primaryButton: .destructive(Text(NFSLocalized.text("移除", "Remove"))) {
                    appState.removeLocation(location)
                },
                secondaryButton: .cancel(Text(NFSLocalized.text("取消", "Cancel")))
            )
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var hasCustomHotKey: Bool {
        customHotKeyKeyCode >= 0 && customHotKeyModifiers > 0
    }

    private var customHotKeyLabel: String {
        let label = customHotKeyDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty
            ? NFSLocalized.text("未设置", "Not set")
            : label
    }

    private var revealShortcutLabel: String {
        let label = revealShortcutDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty
            ? NFSLocalized.text("⌘ 回车", "⌘ Return")
            : label
    }

    private func saveCustomHotKey(keyCode: UInt32, modifiers: UInt32, label: String) {
        GlobalHotKeyConfiguration.saveCustomBinding(
            keyCode: keyCode,
            modifiers: modifiers,
            label: label
        )
        customHotKeyKeyCode = Int(keyCode)
        customHotKeyModifiers = Int(modifiers)
        customHotKeyDisplay = label
        hotKeyPresetRaw = GlobalHotKeyPreset.custom.rawValue
        isRecordingCustomHotKey = false
        NotificationCenter.default.post(name: .nfsHotKeyConfigurationChanged, object: nil)
    }

    private func clearCustomHotKey() {
        GlobalHotKeyConfiguration.clearCustomBinding()
        customHotKeyKeyCode = 0
        customHotKeyModifiers = 0
        customHotKeyDisplay = ""
        if hotKeyPresetRaw == GlobalHotKeyPreset.custom.rawValue {
            hotKeyPresetRaw = GlobalHotKeyPreset.optionSpace.rawValue
        }
        NotificationCenter.default.post(name: .nfsHotKeyConfigurationChanged, object: nil)
    }

    private func saveRevealShortcut(keyCode: UInt32, modifiers: UInt32, label: String) {
        FinderRevealShortcutConfiguration.save(
            keyCode: keyCode,
            modifiers: modifiers,
            displayName: label
        )
        revealShortcutKeyCode = Int(keyCode)
        revealShortcutModifiers = Int(modifiers)
        revealShortcutDisplay = label
        isRecordingRevealShortcut = false
    }

    private func resetRevealShortcut() {
        FinderRevealShortcutConfiguration.reset()
        revealShortcutKeyCode = Int(FinderRevealShortcutConfiguration.defaultKeyCode)
        revealShortcutModifiers = Int(FinderRevealShortcutConfiguration.defaultModifiers)
        revealShortcutDisplay = ""
        isRecordingRevealShortcut = false
    }
}

private struct GlobalHotKeyCaptureView: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onCapture: (UInt32, UInt32, String) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> GlobalHotKeyCaptureNSView {
        let view = GlobalHotKeyCaptureNSView()
        let coordinator = context.coordinator
        view.onCapture = { [weak coordinator] keyCode, modifiers, label in
            coordinator?.parent.isRecording = false
            coordinator?.parent.onCapture(keyCode, modifiers, label)
        }
        view.onCancel = { [weak coordinator] in
            coordinator?.parent.isRecording = false
            coordinator?.parent.onCancel()
        }
        return view
    }

    func updateNSView(_ nsView: GlobalHotKeyCaptureNSView, context: Context) {
        context.coordinator.parent = self
        nsView.isRecording = isRecording

        guard isRecording else { return }
        DispatchQueue.main.async {
            guard nsView.isRecording else { return }
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    final class Coordinator {
        var parent: GlobalHotKeyCaptureView

        init(_ parent: GlobalHotKeyCaptureView) {
            self.parent = parent
        }
    }
}

private final class GlobalHotKeyCaptureNSView: NSView {
    var isRecording = false
    var onCapture: ((UInt32, UInt32, String) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return false }
        return capture(event)
    }

    override func keyDown(with event: NSEvent) {
        _ = capture(event)
    }

    private func capture(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let modifiers = carbonModifiers(for: flags)
        guard modifiers != 0 else {
            if event.keyCode == 53 {
                onCancel?()
                return true
            }
            NSSound.beep()
            return true
        }

        onCapture?(
            UInt32(event.keyCode),
            modifiers,
            hotKeyDisplayName(for: event, flags: flags)
        )
        return true
    }
}

private func carbonModifiers(for flags: NSEvent.ModifierFlags) -> UInt32 {
    var modifiers: UInt32 = 0
    if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
    if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
    if flags.contains(.option) { modifiers |= UInt32(optionKey) }
    if flags.contains(.control) { modifiers |= UInt32(controlKey) }
    return modifiers
}

private func hotKeyDisplayName(for event: NSEvent, flags: NSEvent.ModifierFlags) -> String {
    var parts: [String] = []
    if flags.contains(.control) { parts.append("⌃") }
    if flags.contains(.option) { parts.append("⌥") }
    if flags.contains(.shift) { parts.append("⇧") }
    if flags.contains(.command) { parts.append("⌘") }

    let keyName: String
    switch event.keyCode {
    case UInt16(kVK_Space):
        keyName = NFSLocalized.text("空格", "Space")
    case 36, 76:
        keyName = NFSLocalized.text("回车", "Return")
    case 48:
        keyName = "Tab"
    case 51, 117:
        keyName = NFSLocalized.text("删除", "Delete")
    case 53:
        keyName = "Esc"
    case 123:
        keyName = "←"
    case 124:
        keyName = "→"
    case 125:
        keyName = "↓"
    case 126:
        keyName = "↑"
    default:
        if let characters = event.charactersIgnoringModifiers?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !characters.isEmpty {
            keyName = characters.uppercased()
        } else {
            keyName = "Key \(event.keyCode)"
        }
    }

    parts.append(keyName)
    return parts.joined(separator: " ")
}

struct IndexedLocationRow: View {
    let location: IndexedLocation
    let onTogglePause: () -> Void
    let onRebuild: () -> Void
    let onRemove: () -> Void
    @AppStorage("nfsLanguage") private var languageRaw = AppLanguage.simplifiedChinese.rawValue

    var body: some View {
        HStack(spacing: 10) {
            Image(
                systemName: location.isPaused
                    ? "pause.circle"
                    : (location.isOffline ? "externaldrive.badge.xmark" : "folder")
            )
                .foregroundStyle(
                    location.isPaused || location.isOffline
                        ? Color.secondary
                        : Color.accentColor
                )
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(location.path)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(NFSLocalized.fileCount(location.fileCount.formatted()))
                    if location.isOffline {
                        Text(NFSLocalized.text("暂时离线", "Offline"))
                            .foregroundStyle(.orange)
                    }
                }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(
                location.isPaused
                    ? NFSLocalized.text("继续索引", "Resume")
                    : NFSLocalized.text("暂停索引", "Pause"),
                action: onTogglePause
            )
                .buttonStyle(.borderless)
            Button(NFSLocalized.text("重建", "Rebuild"), action: onRebuild)
                .buttonStyle(.borderless)
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(NFSLocalized.text("从索引中移除文件夹", "Remove folder from index"))
        }
        .padding(.vertical, 5)
    }
}
