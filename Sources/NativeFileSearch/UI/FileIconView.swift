import AppKit
import SwiftUI

struct FileIconView: View {
    let record: FileRecord
    var size: CGFloat = 30
    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: record.isDirectory ? "folder.fill" : "doc")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(record.isDirectory ? Color.accentColor : Color.secondary)
                    .padding(3)
            }
        }
            .frame(width: size, height: size)
            .accessibilityLabel(record.fileTypeLabel)
            .task(id: record.fullPath) {
                icon = nil
                let path = record.fullPath
                let loadedIcon = await Task.detached(priority: .utility) {
                    LoadedFileIcon(NSWorkspace.shared.icon(forFile: path))
                }.value
                guard !Task.isCancelled else { return }
                icon = loadedIcon.image
            }
    }
}

/// NSImage is immutable for our use here, but its Sendable conformance is
/// only available on newer macOS SDKs. Keep the background loading boundary
/// explicit without forcing the app's deployment target forward.
private final class LoadedFileIcon: @unchecked Sendable {
    let image: NSImage

    init(_ image: NSImage) {
        self.image = image
    }
}
