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
            button.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "窗口布局")
            button.image?.isTemplate = true
            button.toolTip = "窗口布局工具"
        }

        let menu = NSMenu()
        menu.delegate = self

        enabledItem.target = self
        enabledItem.action = #selector(toggleEnabled)
        menu.addItem(enabledItem)

        loginItem.title = "开机启动"
        loginItem.target = self
        loginItem.action = #selector(toggleLoginItem)
        menu.addItem(loginItem)

        layoutsItem.title = "布局功能"
        layoutsItem.target = self
        layoutsItem.action = #selector(toggleLayouts)
        menu.addItem(layoutsItem)

        menu.addItem(.separator())
        permissionItem.isEnabled = false
        menu.addItem(permissionItem)

        let requestPermissionItem = NSMenuItem(
            title: "申请辅助功能权限",
            action: #selector(requestPermission),
            keyEquivalent: ""
        )
        requestPermissionItem.target = self
        menu.addItem(requestPermissionItem)

        let settingsItem = NSMenuItem(
            title: "打开系统权限设置…",
            action: #selector(openPermissionSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        let aboutItem = NSMenuItem(title: "关于窗口布局工具", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        refreshMenuState()
    }

    private func refreshMenuState() {
        enabledItem.title = settings.monitoringEnabled ? "暂停" : "启用"
        enabledItem.state = settings.monitoringEnabled ? .on : .off
        loginItem.state = loginItems.isEnabled ? .on : .off
        loginItem.title = loginItems.requiresApproval ? "开机启动（等待系统批准）" : "开机启动"
        layoutsItem.state = settings.layoutsEnabled ? .on : .off
        permissionItem.title = permissions.isTrusted ? "辅助功能权限：已授权" : "辅助功能权限：未授权"
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
            showAlert(title: "无法更改开机启动", message: message)
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
            .applicationName: "窗口布局工具",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            .credits: NSAttributedString(string: "纯本地、原生 AppKit 窗口布局工具。不会连接网络或收集数据。")
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
