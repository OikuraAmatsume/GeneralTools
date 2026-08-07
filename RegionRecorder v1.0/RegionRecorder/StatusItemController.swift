import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let menuProvider: () -> NSMenu

    init(menuProvider: @escaping () -> NSMenu) {
        self.menuProvider = menuProvider
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "ローカル範囲録画")
            button.image?.isTemplate = true
            button.toolTip = "ローカル範囲録画（右クリックでメニューを表示）"
            button.target = self
            button.action = #selector(showMenu(_:))
            button.sendAction(on: [.rightMouseUp])
        }
    }

    func update(isRecording: Bool) {
        guard let button = statusItem.button else { return }
        let symbol = isRecording ? "record.circle.fill" : "record.circle"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "ローカル範囲録画")
        button.image?.isTemplate = true
    }

    @objc private func showMenu(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        let menu = menuProvider()
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: button.bounds.midX, y: button.bounds.minY - 3),
            in: button
        )
    }
}
