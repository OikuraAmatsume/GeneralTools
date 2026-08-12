import AppKit

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let settings: SettingsStore
    private let permissions: PermissionController
    private let loginItems: LoginItemController
    private let cancelCurrentDrag: () -> Void
    private let statusItem: NSStatusItem

    private let enabledItem = NSMenuItem()
    private let loginItem = NSMenuItem()
    private let layoutsItem = NSMenuItem()
    private let permissionItem = NSMenuItem()

    init(
        settings: SettingsStore,
        permissions: PermissionController,
        loginItems: LoginItemController,
        cancelCurrentDrag: @escaping () -> Void
    ) {
        self.settings = settings
        self.permissions = permissions
        self.loginItems = loginItems
        self.cancelCurrentDrag = cancelCurrentDrag
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureStatusItem()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenuState()
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "ウインドウレイアウト")
            button.image?.isTemplate = true
            button.toolTip = "ウインドウレイアウトツール"
        }

        let menu = NSMenu()
        menu.delegate = self

        enabledItem.target = self
        enabledItem.action = #selector(toggleEnabled)
        menu.addItem(enabledItem)

        loginItem.title = "ログイン時に起動"
        loginItem.target = self
        loginItem.action = #selector(toggleLoginItem)
        menu.addItem(loginItem)

        layoutsItem.title = "レイアウト機能"
        layoutsItem.target = self
        layoutsItem.action = #selector(toggleLayouts)
        menu.addItem(layoutsItem)

        menu.addItem(.separator())
        permissionItem.isEnabled = false
        menu.addItem(permissionItem)

        let requestPermissionItem = NSMenuItem(
            title: "アクセシビリティ権限をリクエスト",
            action: #selector(requestPermission),
            keyEquivalent: ""
        )
        requestPermissionItem.target = self
        menu.addItem(requestPermissionItem)

        let settingsItem = NSMenuItem(
            title: "システムの権限設定を開く…",
            action: #selector(openPermissionSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        let aboutItem = NSMenuItem(title: "ウインドウレイアウトツールについて", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "終了", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        refreshMenuState()
    }

    private func refreshMenuState() {
        enabledItem.title = settings.monitoringEnabled ? "一時停止" : "有効にする"
        enabledItem.state = settings.monitoringEnabled ? .on : .off
        loginItem.state = loginItems.isEnabled ? .on : .off
        loginItem.title = loginItems.requiresApproval ? "ログイン時に起動（システムの承認待ち）" : "ログイン時に起動"
        layoutsItem.state = settings.layoutsEnabled ? .on : .off
        permissionItem.title = permissions.isTrusted ? "アクセシビリティ権限：許可済み" : "アクセシビリティ権限：未許可"
    }

    @objc private func toggleEnabled() {
        settings.monitoringEnabled.toggle()
        if !settings.monitoringEnabled { cancelCurrentDrag() }
        refreshMenuState()
    }

    @objc private func toggleLayouts() {
        settings.layoutsEnabled.toggle()
        if !settings.layoutsEnabled { cancelCurrentDrag() }
        refreshMenuState()
    }

    @objc private func toggleLoginItem() {
        switch loginItems.setEnabled(!loginItems.isEnabled) {
        case .success:
            break
        case .requiresApproval:
            loginItems.openLoginItemsSettings()
        case .failed(let message):
            showAlert(title: "ログイン時起動を変更できません", message: message)
        }
        refreshMenuState()
    }

    @objc private func requestPermission() {
        permissions.requestIfNeeded(prompt: true)
        refreshMenuState()
    }

    @objc private func openPermissionSettings() {
        permissions.openSystemSettings()
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "ウインドウレイアウトツール",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            .credits: NSAttributedString(string: "完全ローカルで動作するネイティブ AppKit ウインドウレイアウトツールです。ネットワーク接続やデータ収集は行いません。")
        ])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
