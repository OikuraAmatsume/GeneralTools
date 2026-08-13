import AppKit
import ApplicationServices
import FinderSync
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(
        subsystem: "com.amatsume.AmatsumeInit",
        category: "URLHandler"
    )
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let statusMenu = NSMenu(title: "Amatsume init")
    private let statusMenuItem = NSMenuItem(title: "状态：正在启动", action: nil, keyEquivalent: "")
    private let finderExtensionStatusMenuItem = NSMenuItem(
        title: "Finder 扩展：正在检查",
        action: nil,
        keyEquivalent: ""
    )
    private let keyboardMonitor = KeyboardMonitor()
    private let terminalLauncher = TerminalLauncher()
    private var terminalMenuItems: [TerminalApplication: NSMenuItem] = [:]
    private var permissionTimer: Timer?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleApplicationURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

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

        refreshFinderExtensionStatus()
        offerFinderExtensionSetupIfNeeded()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshFinderExtensionStatus()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        permissionTimer?.invalidate()
        keyboardMonitor.stop()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        button.image = StatusIcon.image(isActive: false)
        button.toolTip = "Amatsume init"
        button.target = self
        button.action = #selector(showStatusMenu(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configureMenu() {
        statusMenu.autoenablesItems = false

        let titleItem = NSMenuItem(title: "Amatsume init", action: nil, keyEquivalent: "")
        titleItem.image = StatusIcon.image(isActive: true)
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

        let finderFeature = NSMenuItem(
            title: "Finder 空白处右键 → CMD here / txt here",
            action: nil,
            keyEquivalent: ""
        )
        finderFeature.indentationLevel = 1
        finderFeature.isEnabled = false
        statusMenu.addItem(finderFeature)
        statusMenu.addItem(.separator())

        configureTerminalMenu()

        finderExtensionStatusMenuItem.isEnabled = false
        statusMenu.addItem(finderExtensionStatusMenuItem)

        let finderSettingsItem = NSMenuItem(
            title: "管理 Finder 扩展…",
            action: #selector(openFinderExtensionSettings),
            keyEquivalent: ""
        )
        finderSettingsItem.target = self
        finderSettingsItem.isEnabled = true
        statusMenu.addItem(finderSettingsItem)
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

    private func configureTerminalMenu() {
        let defaultTerminalItem = NSMenuItem(
            title: "默认终端",
            action: nil,
            keyEquivalent: ""
        )
        let terminalMenu = NSMenu(title: "默认终端")
        terminalMenu.autoenablesItems = false

        for terminal in TerminalApplication.availableApplications {
            let item = NSMenuItem(
                title: terminal.displayName,
                action: #selector(selectDefaultTerminal(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = terminal.rawValue
            item.isEnabled = true
            terminalMenu.addItem(item)
            terminalMenuItems[terminal] = item
        }

        defaultTerminalItem.submenu = terminalMenu
        statusMenu.addItem(defaultTerminalItem)
        updateTerminalSelection()
    }

    private func updateStatus(for state: KeyboardMonitor.State) {
        switch state {
        case .running:
            statusMenuItem.title = "状态：运行中"
            setStatusIcon(isActive: true)
            permissionTimer?.invalidate()
            permissionTimer = nil
        case .permissionRequired:
            statusMenuItem.title = "状态：需要辅助功能权限"
            setStatusIcon(isActive: false)
        case .failed:
            statusMenuItem.title = "状态：无法启动键盘监听"
            setStatusIcon(isActive: false)
        case .stopped:
            statusMenuItem.title = "状态：已停止"
            setStatusIcon(isActive: false)
        }
    }

    private func setStatusIcon(isActive: Bool) {
        statusItem.button?.image = StatusIcon.image(isActive: isActive)
    }

    private func updateTerminalSelection() {
        let selectedTerminal = TerminalApplication.selected

        for (terminal, item) in terminalMenuItems {
            item.state = terminal == selectedTerminal ? .on : .off
        }
    }

    private func refreshFinderExtensionStatus() {
        finderExtensionStatusMenuItem.title = FIFinderSyncController.isExtensionEnabled
            ? "Finder 扩展：已启用"
            : "Finder 扩展：需要启用"
    }

    private func offerFinderExtensionSetupIfNeeded() {
        let defaultsKey = "didOfferFinderExtensionSetupV1"
        guard
            !FIFinderSyncController.isExtensionEnabled,
            !UserDefaults.standard.bool(forKey: defaultsKey)
        else {
            return
        }

        UserDefaults.standard.set(true, forKey: defaultsKey)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            FIFinderSyncController.showExtensionManagementInterface()
        }
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

    @objc private func openFinderExtensionSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    @objc private func selectDefaultTerminal(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let terminal = TerminalApplication(rawValue: rawValue),
            terminal.isAvailable
        else {
            return
        }

        TerminalApplication.selected = terminal
        updateTerminalSelection()
    }

    @objc private func handleApplicationURL(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        guard
            let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
            let url = URL(string: urlString),
            url.scheme == "amatsume-init",
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let path = components.queryItems?.first(where: { $0.name == "path" })?.value
        else {
            logger.error("收到无效的 Amatsume URL")
            return
        }

        let directoryURL = URL(fileURLWithPath: path, isDirectory: true)

        switch url.host {
        case "open-terminal":
            logger.notice("收到 Finder 进入终端请求：\(path, privacy: .public)")
            terminalLauncher.open(directory: directoryURL)
        case "create-text-file":
            logger.notice("收到 Finder 新建文本文件请求：\(path, privacy: .public)")
            createEmptyTextFile(in: directoryURL)
        default:
            logger.error("收到未知的 Amatsume URL 动作")
        }
    }

    private func createEmptyTextFile(in directory: URL) {
        let directoryURL = directory.standardizedFileURL

        guard
            directoryURL.isFileURL,
            (try? directoryURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        else {
            logger.error("无法在无效目录中新建文本文件：\(directoryURL.path, privacy: .public)")
            return
        }

        for index in 1...10_000 {
            let fileName = index == 1 ? "untitled.txt" : "untitled \(index).txt"
            let fileURL = directoryURL.appendingPathComponent(fileName, isDirectory: false)

            do {
                try Data().write(to: fileURL, options: .withoutOverwriting)
                logger.notice("已新建文本文件：\(fileURL.path, privacy: .public)")
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                return
            } catch {
                let cocoaError = error as NSError

                if cocoaError.domain == NSCocoaErrorDomain,
                   cocoaError.code == NSFileWriteFileExistsError {
                    continue
                }

                logger.error("新建文本文件失败：\(error.localizedDescription, privacy: .public)")
                return
            }
        }

        logger.error("新建文本文件失败：可用文件名已耗尽")
    }

    @objc private func showStatusMenu(_ sender: NSStatusBarButton) {
        refreshFinderExtensionStatus()
        updateTerminalSelection()
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
