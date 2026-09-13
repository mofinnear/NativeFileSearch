import AppKit
import SwiftUI

struct SearchWindowView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @FocusState private var searchFieldFocused: Bool

    @State private var selectedPath: String?
    @State private var isAdvancedSearchPresented = false
    @AppStorage("nfsShowSidebar") private var isSidebarVisible = true
    @AppStorage("nfsLanguage") private var languageRaw = AppLanguage.simplifiedChinese.rawValue
    @AppStorage("nfsOpenFileShortcut") private var openFileShortcutRaw = OpenFileShortcut.returnKey.rawValue

    var body: some View {
        HStack(spacing: 0) {
            if isSidebarVisible {
                sidebar
                Divider()
            }
            mainContent
        }
        .frame(minWidth: 1_040, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.locale, Locale(identifier: languageRaw))
        .onAppear {
            selectedPath = appState.selectedResult?.fullPath
            DispatchQueue.main.async {
                searchFieldFocused = true
            }
            appState.scheduleSearch()
        }
        .onChange(of: selectedPath) { newPath in
            appState.select(path: newPath)
        }
        .onChange(of: appState.results) { newResults in
            if let selectedPath, newResults.contains(where: { $0.fullPath == selectedPath }) {
                return
            }
            selectedPath = newResults.first?.fullPath
        }
        .onReceive(NotificationCenter.default.publisher(for: .nfsFocusSearchField)) { _ in
            searchFieldFocused = true
            selectedPath = appState.selectedResult?.fullPath ?? appState.results.first?.fullPath
        }
        .onReceive(NotificationCenter.default.publisher(for: .nfsShowSettingsWindow)) { _ in
            openWindow(id: "settings")
        }
        .background(
            KeyboardCommandMonitor { event in
                handleKey(event)
            }
        )
        .sheet(isPresented: $appState.showOnboarding) {
            OnboardingView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $isAdvancedSearchPresented) {
            AdvancedSearchView(
                filenameRegex: appState.filenameRegex,
                pathRegex: appState.pathRegex,
                extensionFilter: appState.extensionFilter,
                kindFilter: appState.kindFilter
            )
            .environmentObject(appState)
        }
        .alert(item: $appState.pendingTrash) { record in
            Alert(
                title: Text(NFSLocalized.text("移动到废纸篓？", "Move to Trash?")),
                message: Text(record.filename),
                primaryButton: .destructive(Text(NFSLocalized.text("移动到废纸篓", "Move to Trash"))) {
                    appState.moveToTrash(record)
                },
                secondaryButton: .cancel(Text(NFSLocalized.text("取消", "Cancel")))
            )
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarBrand

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(FileCategoryFilter.allCases) { category in
                        SidebarCategoryRow(
                            category: category,
                            count: appState.facetCounts.count(for: category),
                            isSelected: appState.categoryFilter == category
                        ) {
                            appState.categoryFilter = category
                        }
                    }
                }
                .padding(.top, 22)
            }

            Spacer(minLength: 12)

            Divider()
                .padding(.horizontal, 2)

            Button {
                openWindow(id: "settings")
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 22)
                    Text(NFSLocalized.text("设置", "Settings"))
                        .font(.system(size: 13, weight: .medium))
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(NFSLocalized.text("打开设置", "Open Settings"))
        }
        .padding(.horizontal, 14)
        .padding(.top, 18)
        .padding(.bottom, 10)
        .frame(width: 226)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.72))
    }

    private var sidebarBrand: some View {
        HStack(spacing: 11) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .shadow(color: Color.accentColor.opacity(0.18), radius: 9, y: 3)

            VStack(alignment: .leading, spacing: 3) {
                Text("NativeFileSearch")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(NFSLocalized.text("快速本地文件搜索", "Fast local file search"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 5)
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            mainTopBar
            searchArea
            Divider()
            resultHeader
            resultContent
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var mainTopBar: some View {
        HStack(spacing: 10) {
            Button {
                isSidebarVisible.toggle()
            } label: {
                Image(systemName: isSidebarVisible ? "sidebar.left" : "sidebar.right")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(isSidebarVisible
                ? NFSLocalized.text("隐藏侧边栏", "Hide sidebar")
                : NFSLocalized.text("显示侧边栏", "Show sidebar"))

            Spacer(minLength: 8)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var searchArea: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(searchFieldFocused ? Color.accentColor : Color.secondary)

            TextField(
                NFSLocalized.text("搜索文件名、路径或扩展名…", "Search filename, path, or extension…"),
                text: $appState.searchText
            )
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .medium))
                .focused($searchFieldFocused)
                .disableAutocorrection(true)
                .help(NFSLocalized.text(
                    "空格表示同时满足；支持 path:路径、ext:pdf 或 type:pdf，例如：张三小区 201 pdf",
                    "Separate terms with spaces; use path:folder, ext:pdf, or type:pdf. Example: invoice 201 pdf"
                ))

            Button {
                isAdvancedSearchPresented = true
            } label: {
                Image(systemName: hasAdvancedSearch ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(hasAdvancedSearch ? Color.accentColor : Color.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(NFSLocalized.text("打开高级搜索", "Open advanced search"))

            if hasActiveSearch {
                Button {
                    appState.clearSearch()
                    searchFieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(NFSLocalized.text("清除搜索", "Clear search"))
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    searchFieldFocused ? Color.accentColor : Color(nsColor: .separatorColor),
                    lineWidth: searchFieldFocused ? 2 : 1
                )
        )
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .controlBackgroundColor).opacity(0.46)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var resultHeader: some View {
        HStack(spacing: 8) {
            Text(resultSummary)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            if appState.indexingStatus.phase == .indexing {
                ProgressView()
                    .controlSize(.small)
                Text(NFSLocalized.text("正在索引…", "Indexing…"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else if appState.indexingStatus.phase == .error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(NFSLocalized.text("索引需要注意", "Indexing needs attention"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var resultContent: some View {
        if appState.results.isEmpty {
            emptyState
        } else {
            resultList
        }
    }

    private var resultList: some View {
        VStack(spacing: 0) {
            tableHeader

            List(appState.results, selection: $selectedPath) { record in
                ResultRow(
                    record: record,
                    isSelected: selectedPath == record.fullPath,
                    onSelect: {
                        selectedPath = record.fullPath
                        searchFieldFocused = false
                    },
                    onOpen: {
                        appState.open(record)
                    },
                    onReveal: {
                        appState.reveal(record)
                    },
                    onCopy: {
                        appState.copyFile(record)
                    },
                    onCopyPath: {
                        appState.copyPath(record)
                    },
                    onTrash: {
                        appState.requestMoveToTrash(record)
                    }
                )
                .tag(record.fullPath)
                .listRowInsets(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tableHeader: some View {
        HStack(spacing: 14) {
            Text(NFSLocalized.text("名称 / 路径", "Name / Path"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(NFSLocalized.text("修改时间", "Modified"))
                .frame(width: 158, alignment: .leading)
            Text(NFSLocalized.text("大小", "Size"))
                .frame(width: 90, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 24)
        .padding(.vertical, 7)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            if appState.indexedLocations.isEmpty {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                    .shadow(color: Color.accentColor.opacity(0.22), radius: 16, y: 5)
            } else {
                Image(systemName: hasActiveSearch ? "doc.text.magnifyingglass" : "internaldrive")
                    .font(.system(size: 39, weight: .regular))
                    .foregroundStyle(.tertiary)
            }

            Text(emptyStateTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)

            if hasActiveSearch && !appState.indexedLocations.isEmpty {
                Text(NFSLocalized.text("试试其他名称、路径或筛选条件", "Try another name, path, or filter"))
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }

            if !hasActiveSearch && !appState.indexedLocations.isEmpty {
                VStack(spacing: 4) {
                    Text(NFSLocalized.text("输入多个词会同时匹配", "Multiple terms are matched together"))
                    Text(NFSLocalized.text(
                        "例如：张三小区 201 pdf   ·   path:Documents/Job   ·   ext:pdf",
                        "Example: invoice 201 pdf   ·   path:Documents/Job   ·   ext:pdf"
                    ))
                }
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            }

            if appState.indexedLocations.isEmpty {
                Button(NFSLocalized.text("选择要索引的文件夹", "Choose folders to index")) {
                    openWindow(id: "settings")
                }
                .buttonStyle(.link)
                .font(.system(size: 13, weight: .medium))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var bottomBar: some View {
        HStack(spacing: 13) {
            Label(NFSLocalized.text("右键查看更多操作", "Right-click for more actions"), systemImage: "ellipsis.circle")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 8)

            if let notice = appState.notice {
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 180)
            }

            ShortcutHint(key: configuredOpenFileShortcut.keyHint, label: NFSLocalized.text("打开", "Open"))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var resultSummary: String {
        if appState.indexedLocations.isEmpty {
            return NFSLocalized.text("请选择文件夹开始索引", "Choose a folder to start indexing")
        }
        if !hasActiveSearch {
            return NFSLocalized.text("输入关键词开始搜索", "Enter a keyword to search")
        }
        return NFSLocalized.resultSummary(appState.results.count.formatted(), time: searchTimeLabel)
    }

    private var searchTimeLabel: String {
        let milliseconds = max(0, appState.lastSearchMilliseconds)
        if milliseconds < 1_000 {
            return String(format: "%.0f ms", milliseconds)
        }
        return String(format: "%.2f s", milliseconds / 1_000)
    }

    private var hasActiveSearch: Bool {
        !appState.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || hasSecondaryFilters
    }

    private var hasSecondaryFilters: Bool {
        !appState.extensionFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !appState.filenameRegex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !appState.pathRegex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || appState.categoryFilter != .all
            || appState.kindFilter != .all
            || appState.modificationFilter != .any
    }

    private var hasAdvancedSearch: Bool {
        !appState.filenameRegex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !appState.pathRegex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !appState.extensionFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var configuredOpenFileShortcut: OpenFileShortcut {
        OpenFileShortcut(rawValue: openFileShortcutRaw) ?? .returnKey
    }

    private var emptyStateTitle: String {
        if appState.indexedLocations.isEmpty {
            return NFSLocalized.text("还没有索引位置", "No indexed locations yet")
        }
        if !hasActiveSearch && appState.stats.totalCount == 0 {
            return NFSLocalized.text("还没有索引文件", "No indexed files yet")
        }
        return NFSLocalized.text("没有匹配的文件", "No matching files")
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCommand = modifiers.contains(.command)

        if isCommand && event.keyCode == 3 { // F
            searchFieldFocused = true
            return true
        }

        let firstResponder = event.window?.firstResponder
        let isEditingText = searchFieldFocused || firstResponder is NSTextView || firstResponder is NSTextField
        let hasMarkedText = (firstResponder as? NSTextInputClient)?.hasMarkedText() ?? false

        switch event.keyCode {
        case 126: // Up
            guard !appState.results.isEmpty else { return false }
            moveSelection(by: -1)
            return true
        case 125: // Down
            guard !appState.results.isEmpty else { return false }
            moveSelection(by: 1)
            return true
        case 49: // Space
            guard !isEditingText, let record = appState.selectedResult else { return false }
            appState.preview(record)
            return true
        case 31: // ANSI O
            guard isCommand else { return false }
            guard configuredOpenFileShortcut == .commandO,
                  let record = appState.selectedResult else {
                // Consume Command + O when Return is the configured action so
                // it cannot accidentally invoke another open command.
                return true
            }
            appState.open(record)
            return true
        case 36, 76: // Return / keypad Enter
            // Let the active input method commit its composition first. For
            // example, with a Chinese IME "pdf" is still marked text until
            // Return is pressed; opening a result here would swallow that
            // commit event and make the text appear to be missing.
            guard configuredOpenFileShortcut == .returnKey,
                  !isCommand,
                  !hasMarkedText,
                  let record = appState.selectedResult else { return false }
            appState.open(record)
            return true
        default:
            return false
        }
    }

    private func moveSelection(by offset: Int) {
        guard !appState.results.isEmpty else { return }

        let currentIndex: Int
        if let selectedPath,
           let index = appState.results.firstIndex(where: { $0.fullPath == selectedPath }) {
            currentIndex = index
        } else if let selectedResult = appState.selectedResult,
                  let index = appState.results.firstIndex(where: { $0.fullPath == selectedResult.fullPath }) {
            currentIndex = index
        } else {
            currentIndex = offset > 0 ? -1 : appState.results.count
        }

        let nextIndex = min(
            max(currentIndex + offset, 0),
            appState.results.count - 1
        )
        let record = appState.results[nextIndex]
        selectedPath = record.fullPath
        appState.select(path: record.fullPath)
        searchFieldFocused = false
    }

}

private struct SidebarCategoryRow: View {
    let category: FileCategoryFilter
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: category.icon)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 22)

                Text(category.label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))

                Spacer(minLength: 4)

                Text(count.formatted())
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular, design: .rounded))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .padding(.horizontal, 10)
            .frame(height: 37)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.13) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ShortcutHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct ResultRow: View {
    let record: FileRecord
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onReveal: () -> Void
    let onCopy: () -> Void
    let onCopyPath: () -> Void
    let onTrash: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 11) {
                FileIconView(record: record, size: 34)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(record.filename)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .lineLimit(1)
                    }

                    Text(nfsDisplayPath(record.fullPath))
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.80) : Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(record.modificationDate.formatted(date: .numeric, time: .shortened))
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Color.white.opacity(0.86) : Color.secondary)
                .lineLimit(1)
                .frame(width: 158, alignment: .leading)

            Text(humanReadableSize(record.fileSize, isDirectory: record.isDirectory))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(isSelected ? Color.white.opacity(0.86) : Color.secondary)
                .lineLimit(1)
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    isSelected
                        ? Color.accentColor
                        : isHovered
                            ? Color(nsColor: .controlBackgroundColor).opacity(0.72)
                            : Color.clear
                )
        )
        .onHover { isHovered = $0 }
        .onTapGesture {
            onSelect()
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded { onOpen() })
        .contextMenu {
            Button(NFSLocalized.text("打开", "Open"), action: onOpen)
            Button(NFSLocalized.text("在 Finder 中显示", "Reveal in Finder"), action: onReveal)
            Divider()
            Button(NFSLocalized.text("复制", "Copy"), action: onCopy)
            Button(NFSLocalized.text("复制完整路径", "Copy Path"), action: onCopyPath)
            Divider()
            Button(NFSLocalized.text("移动到废纸篓", "Move to Trash"), role: .destructive, action: onTrash)
        }
    }

    private func humanReadableSize(_ bytes: Int64, isDirectory: Bool) -> String {
        if isDirectory { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private func nfsDisplayPath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    guard path != home else { return "~" }
    guard path.hasPrefix(home + "/") else { return path }
    return "~/" + String(path.dropFirst(home.count + 1))
}
