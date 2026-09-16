import AppKit
import Carbon.HIToolbox
import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case shortcuts
    case indexedLocations

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return NFSLocalized.text("通用", "General")
        case .shortcuts: return NFSLocalized.text("快捷键", "Shortcuts")
        case .indexedLocations: return NFSLocalized.text("索引位置", "Indexed Locations")
        }
    }

    var subtitle: String {
        switch self {
        case .general: return NFSLocalized.text("自定义 NativeFileSearch 的行为和外观。", "Customize how NativeFileSearch looks and behaves.")
        case .shortcuts: return NFSLocalized.text("设置唤醒搜索和处理结果时使用的快捷键。", "Set shortcuts for waking the search window and handling results.")
        case .indexedLocations: return NFSLocalized.text("选择需要建立本地索引的文件夹。", "Choose the folders that should be indexed locally.")
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .shortcuts: return "keyboard"
        case .indexedLocations: return "folder"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var locationToRemove: IndexedLocation?
    @State private var selectedSection: SettingsSection = .general
    @AppStorage("nfsLanguage") private var languageRaw = AppLanguage.simplifiedChinese.rawValue
    @AppStorage("nfsShowSidebar") private var showSidebar = true
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
        HStack(spacing: 0) {
            settingsSidebar

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    pageHeader
                    pageContent
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 26)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.locale, Locale(identifier: languageRaw))
        .frame(minWidth: 780, minHeight: 580)
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

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor)
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text("NativeFileSearch")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(NFSLocalized.text("应用设置", "App Settings"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(SettingsSection.allCases) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            selectedSection = section
                        }
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: section.icon)
                                .font(.system(size: 14, weight: .medium))
                                .frame(width: 20)
                            Text(section.title)
                                .font(.system(size: 12, weight: .medium))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(selectedSection == section ? .white : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            selectedSection == section
                                ? Color.accentColor.opacity(0.88)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 20)

            Divider()
                .padding(.horizontal, 8)
                .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 2) {
                Text("NativeFileSearch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("v\(appVersion)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .frame(width: 190)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.65))
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(selectedSection.title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text(selectedSection.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch selectedSection {
        case .general:
            generalPage
        case .shortcuts:
            shortcutsPage
        case .indexedLocations:
            indexedLocationsPage
        }
    }

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard {
                SettingsCardHeader(
                    icon: "globe",
                    title: NFSLocalized.text("语言", "Language"),
                    subtitle: NFSLocalized.text("选择应用的显示语言。", "Choose the display language for the app.")
                )

                Divider()

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(NFSLocalized.text("显示语言", "Display language"))
                            .font(.system(size: 12, weight: .medium))
                        Text(NFSLocalized.text("语言切换会立即生效。", "Changes take effect immediately."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Picker("", selection: $languageRaw) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.label).tag(language.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }
            }

            SettingsCard {
                SettingsCardHeader(
                    icon: "rectangle.leftthird.inset.filled",
                    title: NFSLocalized.text("界面", "Interface"),
                    subtitle: NFSLocalized.text("选择搜索窗口中需要显示的内容。", "Choose what should be visible in the search window.")
                )

                Divider()

                HStack(spacing: 12) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(NFSLocalized.text("显示侧边栏", "Show sidebar"))
                            .font(.system(size: 12, weight: .medium))
                        Text(NFSLocalized.text("在搜索结果窗口左侧显示分类导航。", "Show category navigation on the left of the search window."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Toggle("", isOn: $showSidebar)
                        .labelsHidden()
                }
            }

            SettingsCard {
                HStack(spacing: 12) {
                    Image(systemName: "bolt.horizontal.circle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("NativeFileSearch")
                            .font(.system(size: 12, weight: .semibold))
                        Text(NFSLocalized.text(
                            "使用 SQLite 与 FSEvents 建立本地索引，搜索不依赖 Spotlight。",
                            "Uses SQLite and FSEvents for a local index. Search does not depend on Spotlight."
                        ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var shortcutsPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard {
                SettingsCardHeader(
                    icon: "keyboard",
                    title: NFSLocalized.text("唤醒搜索窗口", "Wake Search Window"),
                    subtitle: NFSLocalized.text("从任何 App 快速打开搜索窗口。", "Open the search window quickly from any app.")
                )

                Divider()

                HStack(spacing: 12) {
                    Image(systemName: "power")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(NFSLocalized.text("启用全局快捷键", "Enable global shortcut"))
                            .font(.system(size: 12, weight: .medium))
                        Text(NFSLocalized.text("应用关闭窗口后仍会安静地驻留在菜单栏。", "The app stays in the menu bar after its window closes."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Toggle("", isOn: $hotKeyEnabled)
                        .labelsHidden()
                }

                Divider()

                HStack(spacing: 12) {
                    Image(systemName: "command")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 22)
                    Text(NFSLocalized.text("唤醒快捷键", "Wake shortcut"))
                        .font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 12)
                    Picker("", selection: $hotKeyPresetRaw) {
                        ForEach(GlobalHotKeyPreset.allCases) { preset in
                            Text(preset.label).tag(preset.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                    .disabled(!hotKeyEnabled)
                }

                Divider()

                HStack(spacing: 12) {
                    Image(systemName: "pencil.and.outline")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(NFSLocalized.text("自定义组合键", "Custom shortcut"))
                            .font(.system(size: 12, weight: .medium))
                        Text(NFSLocalized.text("录制一个包含修饰键的组合键。", "Record a combination that includes a modifier key."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Button {
                        guard hotKeyEnabled else { return }
                        isRecordingCustomHotKey.toggle()
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: isRecordingCustomHotKey ? "record.circle" : "keyboard")
                            Text(isRecordingCustomHotKey
                                ? NFSLocalized.text("取消录制", "Cancel")
                                : customHotKeyLabel)
                                .lineLimit(1)
                        }
                        .frame(minWidth: 154)
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
            }

            SettingsCard {
                SettingsCardHeader(
                    icon: "arrow.turn.down.left",
                    title: NFSLocalized.text("处理搜索结果", "Handle Search Results"),
                    subtitle: NFSLocalized.text("选择打开文件和在 Finder 中显示的方式。", "Choose how to open results or reveal them in Finder.")
                )

                Divider()

                HStack(spacing: 12) {
                    Image(systemName: "arrow.turn.down.left")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(NFSLocalized.text("打开选中的文件", "Open selected file"))
                            .font(.system(size: 12, weight: .medium))
                        Text(NFSLocalized.text("按下所选快捷键打开当前结果。", "Use the selected shortcut to open the current result."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Picker("", selection: $openFileShortcutRaw) {
                        ForEach(OpenFileShortcut.allCases) { shortcut in
                            Text(shortcut.label).tag(shortcut.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }

                Divider()

                HStack(spacing: 12) {
                    Image(systemName: "folder.badge.magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(NFSLocalized.text("在 Finder 中显示", "Reveal in Finder"))
                            .font(.system(size: 12, weight: .medium))
                        Text(NFSLocalized.text("打开所在目录并选中当前项目。", "Open the containing folder and select the item."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Button {
                        isRecordingRevealShortcut.toggle()
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: isRecordingRevealShortcut ? "record.circle" : "keyboard")
                            Text(isRecordingRevealShortcut
                                ? NFSLocalized.text("取消录制", "Cancel")
                                : revealShortcutLabel)
                                .lineLimit(1)
                        }
                        .frame(minWidth: 154)
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
            }
        }
    }

    private var indexedLocationsPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard {
                HStack(alignment: .top, spacing: 12) {
                    SettingsCardHeader(
                        icon: "folder",
                        title: NFSLocalized.text("索引位置", "Indexed Locations"),
                        subtitle: NFSLocalized.text("只会索引你主动添加的文件夹。", "Only folders you add are indexed.")
                    )
                    Spacer(minLength: 12)
                    Button {
                        appState.chooseFolder()
                    } label: {
                        Label(NFSLocalized.text("添加文件夹", "Add Folder"), systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }

                Divider()

                if appState.indexedLocations.isEmpty {
                    VStack(spacing: 9) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 25, weight: .light))
                            .foregroundStyle(.secondary)
                        Text(NFSLocalized.text("还没有索引位置", "No indexed locations yet"))
                            .font(.system(size: 13, weight: .medium))
                        Text(NFSLocalized.text("添加一个文件夹后，应用会在后台建立本地索引。", "Add a folder and the app will build its local index in the background."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                } else {
                    VStack(spacing: 8) {
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
            }

            SettingsCard {
                HStack(alignment: .top, spacing: 12) {
                    SettingsCardHeader(
                        icon: "chart.bar.xaxis",
                        title: NFSLocalized.text("索引状态", "Index Status"),
                        subtitle: NFSLocalized.text("索引完成后即可快速搜索文件名和路径。", "Search is ready as soon as indexing finishes.")
                    )
                    Spacer(minLength: 12)
                    Button(NFSLocalized.text("重建全部", "Rebuild All")) {
                        appState.rebuildAll()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Divider()

                HStack(spacing: 0) {
                    metric(NFSLocalized.text("文件", "Files"), value: appState.stats.fileCount.formatted())
                    metric(NFSLocalized.text("文件夹", "Folders"), value: appState.stats.folderCount.formatted())
                    metric(NFSLocalized.text("数据库大小", "Database"), value: formattedBytes(appState.stats.databaseSize))
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    if let lastIndexDate = lastIndexDate {
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

                    if appState.indexingStatus.phase == .indexing {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            if let currentPath = appState.indexingStatus.currentPath {
                                Text(NFSLocalized.indexingLocation(
                                    currentPath,
                                    count: appState.indexingStatus.processedCount.formatted()
                                ))
                            } else {
                                Text(NFSLocalized.text("正在建立索引…", "Building index…"))
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
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
            }
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var lastIndexDate: Date? {
        appState.indexedLocations.compactMap(\.lastScanDate).max()
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
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

private struct SettingsCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 1)
            )
    }
}

private struct SettingsCardHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
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
        HStack(spacing: 12) {
            Image(
                systemName: location.isPaused
                    ? "pause.circle"
                    : (location.isOffline ? "externaldrive.badge.xmark" : "folder")
            )
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(
                    location.isPaused || location.isOffline
                        ? Color.secondary
                        : Color.accentColor
                )
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(location.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(NFSLocalized.fileCount(location.fileCount.formatted()))
                    if location.isOffline {
                        Text(NFSLocalized.text("暂时离线", "Offline"))
                            .foregroundStyle(.orange)
                    } else if location.isPaused {
                        Text(NFSLocalized.text("已暂停", "Paused"))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Menu {
                Button {
                    onTogglePause()
                } label: {
                    Label(
                        location.isPaused
                            ? NFSLocalized.text("继续索引", "Resume Indexing")
                            : NFSLocalized.text("暂停索引", "Pause Indexing"),
                        systemImage: location.isPaused ? "play.fill" : "pause.fill"
                    )
                }

                Button {
                    onRebuild()
                } label: {
                    Label(NFSLocalized.text("重建此位置", "Rebuild This Location"), systemImage: "arrow.clockwise")
                }

                Divider()

                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label(NFSLocalized.text("移除索引位置", "Remove Indexed Location"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.06), in: Circle())
            }
            .menuStyle(.borderlessButton)
            .help(NFSLocalized.text("更多操作", "More actions"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}
