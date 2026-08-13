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
        let item = NSMenuItem(
            title: "Amatsume：进入终端",
            action: #selector(openTerminal(_:)),
            keyEquivalent: ""
        )

        item.target = self
        item.image = NSImage(
            systemSymbolName: "terminal",
            accessibilityDescription: "Amatsume：进入终端"
        )
        item.representedObject = targetedURL?.path
        menu.addItem(item)
        return menu
    }

    @objc private func openTerminal(_ sender: NSMenuItem) {
        let directoryURL: URL?

        if let representedPath = sender.representedObject as? String {
            directoryURL = URL(fileURLWithPath: representedPath, isDirectory: true)
        } else {
            // Finder does not reliably preserve representedObject when it
            // forwards a Finder Sync menu action back to the extension.
            directoryURL = contextualDirectoryURL ?? controller.targetedURL()
        }

        guard let path = directoryURL?.standardizedFileURL.path else {
            logger.error("Finder 菜单缺少目标目录")
            return
        }

        logger.notice("触发进入终端：\(path, privacy: .public)")

        var components = URLComponents()

        components.scheme = "amatsume-init"
        components.host = "open-terminal"
        components.queryItems = [URLQueryItem(name: "path", value: path)]

        guard let url = components.url else {
            logger.error("无法生成主程序 URL：\(path, privacy: .public)")
            return
        }

        guard NSWorkspace.shared.open(url) else {
            logger.error("无法向 Amatsume init 发送进入终端请求")
            return
        }

        logger.notice("已向主程序发送进入终端请求")
    }
}
