import AppKit
import SwiftUI

struct AdvancedSearchView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var filenameRegex: String
    @State private var pathRegex: String
    @State private var extensionFilter: String
    @State private var kindFilter: FileKindFilter
    @State private var isRegexHelpPresented = false

    init(
        filenameRegex: String,
        pathRegex: String,
        extensionFilter: String,
        kindFilter: FileKindFilter
    ) {
        _filenameRegex = State(initialValue: filenameRegex)
        _pathRegex = State(initialValue: pathRegex)
        _extensionFilter = State(initialValue: extensionFilter)
        _kindFilter = State(initialValue: kindFilter)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(NFSLocalized.text("高级搜索", "Advanced Search"))
                        .font(.title2.weight(.semibold))
                    Text(NFSLocalized.text(
                        "用正则表达式精确组合文件名、路径和类型",
                        "Combine filename, path, and type filters with regular expressions"
                    ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(NFSLocalized.text("关闭", "Close"))
            }

            Divider()
                .padding(.vertical, 18)

            VStack(alignment: .leading, spacing: 14) {
                regexField(
                    title: NFSLocalized.text("文件名正则", "Filename regex"),
                    placeholder: NFSLocalized.text("例如：技术|手册", "Example: technical|manual"),
                    text: $filenameRegex,
                    help: NFSLocalized.text(
                        "匹配文件名；技术|手册表示包含“技术”或“手册”。",
                        "Matches the filename; technical|manual means either word."
                    )
                )

                regexField(
                    title: NFSLocalized.text("路径正则", "Path regex"),
                    placeholder: NFSLocalized.text("例如：/book/ 或 Documents/资料", "Example: /book/ or Documents/Books"),
                    text: $pathRegex,
                    help: NFSLocalized.text(
                        "匹配完整路径；填写 book 即可匹配路径中包含 book 的位置。",
                        "Matches the full path; entering book matches any path containing book."
                    )
                )

                HStack(spacing: 12) {
                    Text(NFSLocalized.text("扩展名", "Extension"))
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 82, alignment: .leading)

                    TextField(
                        NFSLocalized.text("例如：pdf", "Example: pdf"),
                        text: $extensionFilter
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 170)

                    Text(NFSLocalized.text("类型", "Kind"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)

                    Picker("", selection: $kindFilter) {
                        ForEach(FileKindFilter.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)

                    Spacer(minLength: 0)
                }
            }

            Text(NFSLocalized.text(
                "多个条件会同时满足。示例：文件名 技术|手册，路径 /book/，扩展名 pdf。高级搜索仍只查询本地索引，不会扫描磁盘。",
                "All conditions are combined. Example: filename technical|manual, path /book/, extension pdf. Advanced search still queries only the local index."
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)

            Spacer(minLength: 18)

            HStack {
                Button {
                    isRegexHelpPresented = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(NFSLocalized.text("查看正则表达式使用说明", "View regular expression help"))

                Button(NFSLocalized.text("清除条件", "Clear filters"), role: .destructive) {
                    clearFilters()
                }
                .buttonStyle(.borderless)

                Spacer()

                Button(NFSLocalized.text("取消", "Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(NFSLocalized.text("应用搜索", "Apply Search")) {
                    applyFilters()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 580, height: 390)
        .sheet(isPresented: $isRegexHelpPresented) {
            RegexHelpView()
        }
    }

    private func regexField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        help: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 82, alignment: .leading)

            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
                .help(help)
        }
    }

    private func clearFilters() {
        filenameRegex = ""
        pathRegex = ""
        extensionFilter = ""
        kindFilter = .all
        appState.clearSearch()
        dismiss()
    }

    private func applyFilters() {
        let trimmedFilenameRegex = filenameRegex.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPathRegex = pathRegex.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExtension = extensionFilter.trimmingCharacters(in: .whitespacesAndNewlines)

        appState.applyAdvancedSearch(
            displayText: generatedSearchText(
                filenameRegex: trimmedFilenameRegex,
                pathRegex: trimmedPathRegex,
                extensionFilter: trimmedExtension,
                kindFilter: kindFilter
            ),
            filenameRegex: trimmedFilenameRegex,
            pathRegex: trimmedPathRegex,
            extensionFilter: trimmedExtension,
            kindFilter: kindFilter
        )
        dismiss()
    }

    private func generatedSearchText(
        filenameRegex: String,
        pathRegex: String,
        extensionFilter: String,
        kindFilter: FileKindFilter
    ) -> String {
        var parts: [String] = []

        if !filenameRegex.isEmpty {
            // Keep the search bar friendly for people who do not know regex:
            // "技术|手册" is displayed as the two remembered filename clues.
            let readableFilename = filenameRegex
                .replacingOccurrences(of: ".*", with: "")
                .replacingOccurrences(of: "|", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !readableFilename.isEmpty {
                parts.append(readableFilename)
            }
        }

        if !pathRegex.isEmpty {
            parts.append("path:\(pathRegex)")
        }

        if !extensionFilter.isEmpty {
            let readableExtension = extensionFilter.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            if !readableExtension.isEmpty {
                parts.append("ext:\(readableExtension)")
            }
        }

        switch kindFilter {
        case .all:
            break
        case .files:
            parts.append(NFSLocalized.text("文件", "files"))
        case .folders:
            parts.append(NFSLocalized.text("文件夹", "folders"))
        }

        return parts.joined(separator: " ")
    }
}

private struct RegexHelpView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var copiedPattern: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(NFSLocalized.text("正则表达式说明", "Regular Expression Help"))
                        .font(.title2.weight(.semibold))
                    Text(NFSLocalized.text(
                        "用少量规则描述你记得的文件特征",
                        "Describe remembered file details with a few compact rules"
                    ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Divider()
                .padding(.vertical, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    helpSection(
                        title: NFSLocalized.text("常用写法", "Common patterns"),
                        rows: [
                            ("技术", NFSLocalized.text("文件名中包含“技术”", "Filename contains technical")),
                            ("技术|手册", NFSLocalized.text("包含“技术”或“手册”", "Contains technical or manual")),
                            ("^技术", NFSLocalized.text("文件名以“技术”开头", "Filename starts with technical")),
                            ("手册$", NFSLocalized.text("文件名以“手册”结尾", "Filename ends with manual")),
                            (".*技术.*", NFSLocalized.text("任意位置包含“技术”", "Contains technical anywhere")),
                            ("[0-9]+", NFSLocalized.text("包含一个或多个数字", "Contains one or more digits")),
                            ("202[0-9]", NFSLocalized.text("匹配 2020–2029", "Matches 2020–2029")),
                            ("\\.", NFSLocalized.text("匹配一个真正的句点 .", "Matches a literal period ."))
                        ]
                    )

                    helpSection(
                        title: NFSLocalized.text("三个输入框怎么配合", "How the three fields work together"),
                        rows: [
                            ("技术|手册", NFSLocalized.text("文件名二选一", "Either filename word")),
                            ("/book/", NFSLocalized.text("路径中包含 book 目录", "Path contains the book folder")),
                            ("pdf", NFSLocalized.text("只保留 PDF 文件", "Keep PDF files only"))
                        ]
                    )

                    Text(NFSLocalized.text(
                        "多个字段会同时满足（AND）。正则中的 | 表示二选一（OR）。正则搜索只查询本地索引，不会重新扫描磁盘。匹配默认不区分英文字母大小写。",
                        "All fields must match (AND). The | symbol means either option (OR). Regex search queries only the local index and does not rescan the disk. English letter matching is case-insensitive."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button(NFSLocalized.text("知道了", "Done")) {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 16)
        }
        .padding(24)
        .frame(width: 600, height: 570)
    }

    private func helpSection(title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Button {
                        copyPattern(row.0)
                    } label: {
                        HStack(spacing: 6) {
                            Text(row.0)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(Color.accentColor)

                            if copiedPattern == row.0 {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.green)
                            }
                        }
                        .frame(minWidth: 145, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(NFSLocalized.text("点击复制此规则", "Click to copy this pattern"))

                    Text(row.1)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func copyPattern(_ pattern: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pattern, forType: .string)
        copiedPattern = pattern

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if copiedPattern == pattern {
                copiedPattern = nil
            }
        }
    }
}
