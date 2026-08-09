import AppKit

@MainActor
final class GlobalDragMonitor {
    private var mouseMonitor: Any?
    private var keyboardMonitor: Any?

    private let onMouseDown: (CGPoint) -> Void
    private let onMouseDragged: (CGPoint) -> Void
    private let onMouseUp: (CGPoint) -> Void
    private let onEscape: () -> Void

    init(
        onMouseDown: @escaping (CGPoint) -> Void,
        onMouseDragged: @escaping (CGPoint) -> Void,
        onMouseUp: @escaping (CGPoint) -> Void,
        onEscape: @escaping () -> Void
    ) {
        self.onMouseDown = onMouseDown
        self.onMouseDragged = onMouseDragged
        self.onMouseUp = onMouseUp
        self.onEscape = onEscape
    }

    func start() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            let point = NSEvent.mouseLocation
            DispatchQueue.main.async {
                guard let self else { return }
                switch event.type {
                case .leftMouseDown: self.onMouseDown(point)
                case .leftMouseDragged: self.onMouseDragged(point)
                case .leftMouseUp: self.onMouseUp(point)
                default: break
                }
            }
        }

        keyboardMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            DispatchQueue.main.async { self?.onEscape() }
        }
    }

    func stop() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
        mouseMonitor = nil
        keyboardMonitor = nil
    }

    deinit {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
    }
}
