import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let globalHotKeyManager = GlobalHotKeyManager()
    private var statusItem: NSStatusItem?
    private var languageObserver: NSObjectProtocol?
    private var windowObserver: NSObjectProtocol?
    private var isQuitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()
        globalHotKeyManager.start()

        languageObserver = NotificationCenter.default.addObserver(
            forName: .nfsLanguageChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.statusItem?.menu = self?.makeStatusMenu()
        }

        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            self?.protectSearchWindow(window)
        }
        DispatchQueue.main.async { [weak self] in
            self?.protectSearchWindows()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let languageObserver {
            NotificationCenter.default.removeObserver(languageObserver)
            self.languageObserver = nil
        }
        if let windowObserver {
            NotificationCenter.default.removeObserver(windowObserver)
            self.windowObserver = nil
        }
        globalHotKeyManager.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // The search window is a transient surface. The menu bar item and the
        // file watcher should remain alive after the window is closed.
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSearch()
        return true
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "NativeFileSearch")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "NativeFileSearch"
        }
        item.menu = makeStatusMenu()
        statusItem = item
    }

    private func protectSearchWindows() {
        for window in NSApp.windows {
            protectSearchWindow(window)
        }
    }

    private func protectSearchWindow(_ window: NSWindow) {
        guard window.identifier?.rawValue == "search" || window.title == "NativeFileSearch" else { return }
        window.delegate = self
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !isQuitting,
              (sender.identifier?.rawValue == "search" || sender.title == "NativeFileSearch") else {
            return true
        }

        // Closing the main window hides it but leaves the indexer, watcher,
        // hot key, and menu bar item running for the next wake-up.
        sender.orderOut(nil)
        return false
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let openItem = NSMenuItem(
            title: NFSLocalized.text("打开搜索", "Open Search"),
            action: #selector(showSearch),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)

        let settingsItem = NSMenuItem(
            title: NFSLocalized.text("设置…", "Settings…"),
            action: #selector(showSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: NFSLocalized.text("退出 NativeFileSearch", "Quit NativeFileSearch"),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    @objc private func showSearch() {
        NotificationCenter.default.post(name: .nfsShowSearchWindow, object: nil)
    }

    @objc private func showSettings() {
        NotificationCenter.default.post(name: .nfsShowSettingsWindow, object: nil)
    }

    @objc private func quit() {
        isQuitting = true
        NSApp.terminate(nil)
    }
}
