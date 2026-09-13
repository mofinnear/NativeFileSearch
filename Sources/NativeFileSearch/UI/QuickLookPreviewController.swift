import AppKit
import QuickLookUI

/// Small AppKit bridge used by the SwiftUI result list for the native macOS
/// Quick Look panel. It keeps preview state out of the view hierarchy and
/// reuses the system's preview providers for PDFs, images, office documents,
/// folders, and other supported file types.
final class QuickLookPreviewController: NSObject, QLPreviewPanelDataSource {
    private var previewURL: NSURL?

    func show(_ record: FileRecord) {
        previewURL = NSURL(fileURLWithPath: record.fullPath)

        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int {
        previewURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> QLPreviewItem {
        previewURL ?? NSURL(fileURLWithPath: "/")
    }
}
