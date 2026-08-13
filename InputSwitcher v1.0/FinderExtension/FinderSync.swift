import AppKit
import FinderSync
import OSLog

final class FinderSync: FIFinderSync {
    private let controller = FIFinderSyncController.default()
    private var contextualDirectoryURL: URL?
    private let logger = Logger(
        subsystem: "com.amatsume.AmatsumeInit.FinderExtension",
        category: "FinderAction"
    )

    override init() {
        super.init()

        // Register the file-system root so the container menu is available in
        // every regular Finder folder, including mounted external volumes.
        controller.directoryURLs = [URL(fileURLWithPath: "/", isDirectory: true)]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForContainer else { return nil }

        let targetedURL = controller.targetedURL()?.standardizedFileURL
        contextualDirectoryURL = targetedURL

        if let targetedURL {
            logger.notice("生成 Finder 菜单：\(targetedURL.path, privacy: .public)")
        } else {
            logger.error("生成 Finder 菜单时无法获取目标目录")
        }

        let menu = NSMenu(title: "Amatsume init")
        let terminalItem = NSMenuItem(
            title: "CMD here",
            action: #selector(openTerminal(_:)),
            keyEquivalent: ""
        )

        terminalItem.target = self
        terminalItem.image = NSImage(
            systemSymbolName: "terminal",
            accessibilityDescription: "CMD here"
        )
        terminalItem.representedObject = targetedURL?.path
        menu.addItem(terminalItem)

        let textFileItem = NSMenuItem(
            title: "txt here",
            action: #selector(createTextFile(_:)),
            keyEquivalent: ""
        )

        textFileItem.target = self
        textFileItem.image = NSImage(
            systemSymbolName: "doc.badge.plus",
            accessibilityDescription: "txt here"
        )
        textFileItem.representedObject = targetedURL?.path
        menu.addItem(textFileItem)
        return menu
    }

    @objc private func openTerminal(_ sender: NSMenuItem) {
        sendRequest(host: "open-terminal", actionName: "进入终端", sender: sender)
    }

    @objc private func createTextFile(_ sender: NSMenuItem) {
        sendRequest(host: "create-text-file", actionName: "新建文本文件", sender: sender)
    }

    private func sendRequest(host: String, actionName: String, sender: NSMenuItem) {
        let directoryURL: URL?

        if let representedPath = sender.representedObject as? String {
            directoryURL = URL(fileURLWithPath: representedPath, isDirectory: true)
        } else {
            // Finder does not reliably preserve representedObject when it
            // forwards a Finder Sync menu action back to the extension.
            directoryURL = contextualDirectoryURL ?? controller.targetedURL()
        }

        guard let path = directoryURL?.standardizedFileURL.path else {
            logger.error("Finder 菜单缺少目标目录：\(actionName, privacy: .public)")
            return
        }

        logger.notice("触发\(actionName, privacy: .public)：\(path, privacy: .public)")

        var components = URLComponents()

        components.scheme = "amatsume-init"
        components.host = host
        components.queryItems = [URLQueryItem(name: "path", value: path)]

        guard let url = components.url else {
            logger.error("无法生成主程序 URL：\(actionName, privacy: .public)")
            return
        }

        guard NSWorkspace.shared.open(url) else {
            logger.error("无法向 Amatsume init 发送请求：\(actionName, privacy: .public)")
            return
        }

        logger.notice("已向主程序发送请求：\(actionName, privacy: .public)")
    }
}
