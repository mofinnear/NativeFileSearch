import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .simplifiedChinese: return "简体中文"
        case .english: return "English"
        }
    }

    var isEnglish: Bool { self == .english }

    static var current: AppLanguage {
        guard let rawValue = UserDefaults.standard.string(forKey: "nfsLanguage"),
              let language = AppLanguage(rawValue: rawValue) else {
            return .simplifiedChinese
        }
        return language
    }
}

enum NFSLocalized {
    static func text(_ chinese: String, _ english: String) -> String {
        AppLanguage.current.isEnglish ? english : chinese
    }

    static func fileCount(_ count: String) -> String {
        text("\(count) 个文件", "\(count) files")
    }

    static func folderCount(_ count: String) -> String {
        text("\(count) 个文件夹", "\(count) folders")
    }

    static func resultSummary(_ count: String, time: String) -> String {
        text("找到 \(count) 个结果（\(time)）", "\(count) results (\(time))")
    }

    static func copying(_ filename: String) -> String {
        text("已复制：\(filename)", "Copied: \(filename)")
    }

    static var copiedPath: String {
        text("已复制完整路径", "Copied full path")
    }

    static func movedToTrash(_ filename: String) -> String {
        text("已移到废纸篓：\(filename)", "Moved to Trash: \(filename)")
    }

    static func unableToTrash(_ filename: String, error: String) -> String {
        text("无法移到废纸篓：\(filename)（\(error)）", "Could not move \(filename) to Trash (\(error))")
    }

    static func indexingLocation(_ path: String, count: String) -> String {
        text("正在索引：\(path) · \(count) 项", "Indexing: \(path) · \(count) items")
    }

    static func indexingWarning(_ error: String) -> String {
        text("部分内容无法索引：\(error)", "Some items could not be indexed: \(error)")
    }
}
