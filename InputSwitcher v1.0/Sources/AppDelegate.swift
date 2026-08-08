import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let statusMenu = NSMenu(title: "Amatsume init")
    private let statusMenuItem = NSMenuItem(title: "状态：正在启动", action: nil, keyEquivalent: "")
    private let keyboardMonitor = KeyboardMonitor()
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configureMenu()

        keyboardMonitor.onStateChange = { [weak self] state in
            DispatchQueue.main.async {
                self?.updateStatus(for: state)
            }
        }

        if !keyboardMonitor.start(promptForPermission: true) {
            startPermissionTimer()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        keyboardMonitor.stop()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        let icon = NSImage(
            systemSymbolName: "globe",
            accessibilityDescription: "Amatsume init"
        )
        icon?.isTemplate = true
        button.image = icon
        button.toolTip = "Amatsume init"
        button.target = self
        button.action = #selector(showStatusMenu(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configureMenu() {
        statusMenu.autoenablesItems = false

        let titleItem = NSMenuItem(title: "Amatsume init", action: nil, keyEquivalent: "")
        titleItem.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        titleItem.isEnabled = false
        statusMenu.addItem(titleItem)

        statusMenuItem.isEnabled = false
        statusMenu.addItem(statusMenuItem)
        statusMenu.addItem(.separator())

        let featureHeader = NSMenuItem(title: "功能", action: nil, keyEquivalent: "")
        featureHeader.isEnabled = false
        statusMenu.addItem(featureHeader)

        let f13Feature = NSMenuItem(title: "F13 → 切换输入法", action: nil, keyEquivalent: "")
        f13Feature.indentationLevel = 1
        f13Feature.isEnabled = false
        statusMenu.addItem(f13Feature)

        let shortcutFeature = NSMenuItem(title: "系统快捷键：Control–空格", action: nil, keyEquivalent: "")
        shortcutFeature.indentationLevel = 1
        shortcutFeature.isEnabled = false
        statusMenu.addItem(shortcutFeature)
        statusMenu.addItem(.separator())

        let retryItem = NSMenuItem(
            title: "检查权限并启动",
            action: #selector(retryKeyboardMonitor),
            keyEquivalent: ""
        )
        retryItem.target = self
        retryItem.isEnabled = true
        statusMenu.addItem(retryItem)

        let settingsItem = NSMenuItem(
            title: "打开辅助功能设置…",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        settingsItem.isEnabled = true
        statusMenu.addItem(settingsItem)
        statusMenu.addItem(.separator())

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        let versionItem = NSMenuItem(
            title: "版本 " + version + "（" + build + "）",
            action: nil,
            keyEquivalent: ""
        )
        versionItem.isEnabled = false
        statusMenu.addItem(versionItem)

        let quitItem = NSMenuItem(
            title: "退出 Amatsume init",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.isEnabled = true
        statusMenu.addItem(quitItem)
    }

    private func updateStatus(for state: KeyboardMonitor.State) {
        switch state {
        case .running:
            statusMenuItem.title = "状态：运行中"
            setStatusIcon(symbolName: "globe")
            permissionTimer?.invalidate()
            permissionTimer = nil
        case .permissionRequired:
            statusMenuItem.title = "状态：需要辅助功能权限"
            setStatusIcon(symbolName: "exclamationmark.triangle")
        case .failed:
            statusMenuItem.title = "状态：无法启动键盘监听"
            setStatusIcon(symbolName: "exclamationmark.triangle")
        case .stopped:
            statusMenuItem.title = "状态：已停止"
            setStatusIcon(symbolName: "globe")
        }
    }

    private func setStatusIcon(symbolName: String) {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Amatsume init")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    private func startPermissionTimer() {
        guard permissionTimer == nil else { return }

        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            guard AXIsProcessTrusted() else { return }
            self?.keyboardMonitor.start(promptForPermission: false)
        }

        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    @objc private func retryKeyboardMonitor() {
        if !keyboardMonitor.start(promptForPermission: true) {
            startPermissionTimer()
        }
    }

    @objc private func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }

        NSWorkspace.shared.open(url)
    }

    @objc private func showStatusMenu(_ sender: NSStatusBarButton) {
        statusMenu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: sender.bounds.height + 2),
            in: sender
        )
    }

    @objc private func quitApplication() {
        NSApplication.shared.terminate(nil)
    }
}
