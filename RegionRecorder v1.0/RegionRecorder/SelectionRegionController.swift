import AppKit

@MainActor
final class SelectionRegionController: NSObject {
    private enum Constants {
        static let borderWidth: CGFloat = 2
        static let edgeHitWidth: CGFloat = 12
        static let cornerHitSize: CGFloat = 18
    }

    private(set) var captureFrame: CGRect = .zero
    private(set) var screen: NSScreen?
    private(set) var isLocked = false

    var hasRegion: Bool { outlineWindow?.isVisible == true }
    var onFrameChanged: ((CGRect) -> Void)?

    private var outlineWindow: SelectionPanel?
    private var handleWindows: [SelectionHandle: SelectionPanel] = [:]
    private var sizeWindow: SelectionPanel?
    private var screenChangeObserver: NSObjectProtocol?

    override init() {
        super.init()
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.screenConfigurationChanged() }
        }
    }

    deinit {
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }
    }

    func createDefaultRegion() {
        close()

        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = Self.screen(containing: mouseLocation) ?? NSScreen.main ?? NSScreen.screens.first
        guard let targetScreen else { return }

        let bounds = targetScreen.visibleFrame
        let desiredWidth = min(960, max(CaptureGeometry.minimumCaptureSize.width, bounds.width * 0.66))
        let desiredHeight = min(540, max(CaptureGeometry.minimumCaptureSize.height, bounds.height * 0.66))
        let proposed = CGRect(
            x: bounds.midX - desiredWidth / 2,
            y: bounds.midY - desiredHeight / 2,
            width: desiredWidth,
            height: desiredHeight
        )

        screen = targetScreen
        captureFrame = CaptureGeometry.clamped(proposed, to: bounds)
        buildWindows()
        updateWindowFrames(orderFront: true)
        onFrameChanged?(captureFrame)
    }

    func close() {
        outlineWindow?.close()
        outlineWindow = nil
        handleWindows.values.forEach { $0.close() }
        handleWindows.removeAll()
        sizeWindow?.close()
        sizeWindow = nil
        screen = nil
        captureFrame = .zero
        isLocked = false
    }

    func setLocked(_ locked: Bool) {
        isLocked = locked
        handleWindows.values.forEach { $0.ignoresMouseEvents = locked }
        (outlineWindow?.contentView as? SelectionOutlineView)?.isRecording = locked
        outlineWindow?.contentView?.needsDisplay = true
        hideSizeLabel()
    }

    func descriptor() -> CaptureRegionDescriptor? {
        guard let screen, let displayID = screen.directDisplayID, hasRegion else { return nil }
        return CaptureRegionDescriptor(
            displayID: displayID,
            screenFrame: screen.frame,
            captureFrame: captureFrame,
            backingScaleFactor: screen.backingScaleFactor
        )
    }

    fileprivate func drag(
        handle: SelectionHandle,
        interaction: HandleInteraction,
        startFrame: CGRect,
        startMouse: CGPoint,
        currentMouse: CGPoint
    ) {
        guard !isLocked, let currentScreen = screen else { return }
        let delta = CGPoint(x: currentMouse.x - startMouse.x, y: currentMouse.y - startMouse.y)

        switch interaction {
        case .move:
            let targetScreen = Self.screen(containing: currentMouse) ?? currentScreen
            var proposed = startFrame
            proposed.origin.x += delta.x
            proposed.origin.y += delta.y
            screen = targetScreen
            captureFrame = CaptureGeometry.clamped(proposed, to: targetScreen.visibleFrame)

        case .resize:
            let bounds = currentScreen.visibleFrame
            let minimum = CaptureGeometry.minimumCaptureSize
            var minX = startFrame.minX
            var maxX = startFrame.maxX
            var minY = startFrame.minY
            var maxY = startFrame.maxY

            if handle.affectsLeft {
                minX = min(max(startFrame.minX + delta.x, bounds.minX), startFrame.maxX - minimum.width)
            }
            if handle.affectsRight {
                maxX = max(min(startFrame.maxX + delta.x, bounds.maxX), startFrame.minX + minimum.width)
            }
            if handle.affectsBottom {
                minY = min(max(startFrame.minY + delta.y, bounds.minY), startFrame.maxY - minimum.height)
            }
            if handle.affectsTop {
                maxY = max(min(startFrame.maxY + delta.y, bounds.maxY), startFrame.minY + minimum.height)
            }

            captureFrame = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).integral
            showSizeLabel()
        }

        updateWindowFrames(orderFront: false)
        onFrameChanged?(captureFrame)
    }

    fileprivate func finishDrag(interaction: HandleInteraction) {
        if interaction == .resize {
            hideSizeLabel()
        }
    }

    private func buildWindows() {
        let outline = SelectionPanel(contentRect: .zero)
        outline.ignoresMouseEvents = true
        outline.contentView = SelectionOutlineView(frame: .zero)
        outlineWindow = outline

        for handle in SelectionHandle.allCases {
            let panel = SelectionPanel(contentRect: .zero)
            panel.ignoresMouseEvents = false
            panel.contentView = SelectionHandleView(handle: handle, controller: self)
            handleWindows[handle] = panel
        }

        let labelWindow = SelectionPanel(contentRect: .zero)
        labelWindow.ignoresMouseEvents = true
        labelWindow.contentView = SelectionSizeView(frame: .zero)
        labelWindow.orderOut(nil)
        sizeWindow = labelWindow
    }

    private func updateWindowFrames(orderFront: Bool) {
        guard captureFrame.width > 0, captureFrame.height > 0 else { return }

        let borderInset = Constants.borderWidth / 2
        outlineWindow?.setFrame(captureFrame.insetBy(dx: -borderInset, dy: -borderInset), display: true)

        for (handle, panel) in handleWindows {
            panel.setFrame(frame(for: handle), display: false)
        }

        if sizeWindow?.isVisible == true {
            positionSizeLabel()
        }

        if orderFront {
            outlineWindow?.orderFrontRegardless()
            handleWindows.values.forEach { $0.orderFrontRegardless() }
        }
    }

    private func frame(for handle: SelectionHandle) -> CGRect {
        let edge = Constants.edgeHitWidth
        let corner = Constants.cornerHitSize

        switch handle {
        case .left:
            return CGRect(x: captureFrame.minX - edge / 2, y: captureFrame.minY + corner / 2,
                          width: edge, height: max(1, captureFrame.height - corner))
        case .right:
            return CGRect(x: captureFrame.maxX - edge / 2, y: captureFrame.minY + corner / 2,
                          width: edge, height: max(1, captureFrame.height - corner))
        case .bottom:
            return CGRect(x: captureFrame.minX + corner / 2, y: captureFrame.minY - edge / 2,
                          width: max(1, captureFrame.width - corner), height: edge)
        case .top:
            return CGRect(x: captureFrame.minX + corner / 2, y: captureFrame.maxY - edge / 2,
                          width: max(1, captureFrame.width - corner), height: edge)
        case .bottomLeft:
            return CGRect(x: captureFrame.minX - corner / 2, y: captureFrame.minY - corner / 2,
                          width: corner, height: corner)
        case .bottomRight:
            return CGRect(x: captureFrame.maxX - corner / 2, y: captureFrame.minY - corner / 2,
                          width: corner, height: corner)
        case .topLeft:
            return CGRect(x: captureFrame.minX - corner / 2, y: captureFrame.maxY - corner / 2,
                          width: corner, height: corner)
        case .topRight:
            return CGRect(x: captureFrame.maxX - corner / 2, y: captureFrame.maxY - corner / 2,
                          width: corner, height: corner)
        }
    }

    private func showSizeLabel() {
        guard let sizeView = sizeWindow?.contentView as? SelectionSizeView else { return }
        sizeView.text = "\(Int(captureFrame.width)) × \(Int(captureFrame.height))"
        positionSizeLabel()
        sizeWindow?.orderFrontRegardless()
    }

    private func positionSizeLabel() {
        guard let screen else { return }
        let size = CGSize(width: 126, height: 30)
        var origin = CGPoint(x: captureFrame.midX - size.width / 2, y: captureFrame.maxY + 8)
        if origin.y + size.height > screen.visibleFrame.maxY {
            origin.y = captureFrame.maxY - size.height - 8
        }
        origin.x = min(max(origin.x, screen.visibleFrame.minX), screen.visibleFrame.maxX - size.width)
        sizeWindow?.setFrame(CGRect(origin: origin, size: size), display: true)
    }

    private func hideSizeLabel() {
        sizeWindow?.orderOut(nil)
    }

    private func screenConfigurationChanged() {
        guard hasRegion else { return }
        let current = screen.flatMap { old in
            NSScreen.screens.first { $0.directDisplayID == old.directDisplayID }
        } ?? Self.screen(containing: captureFrame.center) ?? NSScreen.main

        guard let current else {
            close()
            return
        }

        screen = current
        captureFrame = CaptureGeometry.clamped(captureFrame, to: current.visibleFrame)
        updateWindowFrames(orderFront: true)
        onFrameChanged?(captureFrame)
    }

    private static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

final class SelectionPanel: NSPanel {
    convenience init(contentRect: CGRect) {
        self.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class SelectionOutlineView: NSView {
    var isRecording = false
    private let hitBand: CGFloat = 7

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let borderRect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(rect: borderRect)
        path.lineWidth = 2
        (isRecording ? NSColor.systemRed : NSColor.systemBlue).setStroke()
        path.stroke()
    }

    /// Custom hit testing documents the region's interaction contract: only the rim
    /// is interactive. The owner window additionally ignores events and uses narrow
    /// edge panels, which is what guarantees true cross-application click-through.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        return bounds.insetBy(dx: hitBand, dy: hitBand).contains(point) ? nil : self
    }
}

enum HandleInteraction: Equatable {
    case move
    case resize
}

enum SelectionHandle: CaseIterable {
    case left, right, bottom, top
    case bottomLeft, bottomRight, topLeft, topRight

    var isCorner: Bool {
        switch self {
        case .bottomLeft, .bottomRight, .topLeft, .topRight: true
        default: false
        }
    }

    var affectsLeft: Bool { self == .left || self == .bottomLeft || self == .topLeft }
    var affectsRight: Bool { self == .right || self == .bottomRight || self == .topRight }
    var affectsBottom: Bool { self == .bottom || self == .bottomLeft || self == .bottomRight }
    var affectsTop: Bool { self == .top || self == .topLeft || self == .topRight }
}

@MainActor
final class SelectionHandleView: NSView {
    private let handle: SelectionHandle
    private weak var controller: SelectionRegionController?
    private var trackingAreaReference: NSTrackingArea?
    private var dragInteraction: HandleInteraction = .resize
    private var startFrame: CGRect = .zero
    private var startMouse: CGPoint = .zero

    init(handle: SelectionHandle, controller: SelectionRegionController) {
        self.handle = handle
        self.controller = controller
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }
    override var isOpaque: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        trackingAreaReference = tracking
    }

    override func cursorUpdate(with event: NSEvent) {
        cursor(for: interaction(at: convert(event.locationInWindow, from: nil))).set()
    }

    override func mouseMoved(with event: NSEvent) {
        cursor(for: interaction(at: convert(event.locationInWindow, from: nil))).set()
    }

    override func mouseDown(with event: NSEvent) {
        guard let controller, !controller.isLocked else { return }
        dragInteraction = interaction(at: convert(event.locationInWindow, from: nil))
        startFrame = controller.captureFrame
        startMouse = NSEvent.mouseLocation
        cursor(for: dragInteraction, dragging: true).set()
    }

    override func mouseDragged(with event: NSEvent) {
        controller?.drag(
            handle: handle,
            interaction: dragInteraction,
            startFrame: startFrame,
            startMouse: startMouse,
            currentMouse: NSEvent.mouseLocation
        )
        cursor(for: dragInteraction, dragging: true).set()
    }

    override func mouseUp(with event: NSEvent) {
        controller?.finishDrag(interaction: dragInteraction)
        cursor(for: interaction(at: convert(event.locationInWindow, from: nil))).set()
    }

    private func interaction(at point: CGPoint) -> HandleInteraction {
        guard !handle.isCorner else { return .resize }
        let distance: CGFloat
        switch handle {
        case .left, .right:
            distance = abs(point.x - bounds.midX)
        case .top, .bottom:
            distance = abs(point.y - bounds.midY)
        default:
            return .resize
        }
        // The visible 2 pt border moves the entire region. The grab bands immediately
        // beside it resize the corresponding side.
        return distance <= 1.5 ? .move : .resize
    }

    private func cursor(for interaction: HandleInteraction, dragging: Bool = false) -> NSCursor {
        if interaction == .move {
            return dragging ? .closedHand : .openHand
        }

        switch handle {
        case .left, .right:
            return .resizeLeftRight
        case .top, .bottom:
            return .resizeUpDown
        case .topLeft, .bottomRight:
            return ResizeCursorFactory.northwestSoutheast
        case .topRight, .bottomLeft:
            return ResizeCursorFactory.northeastSouthwest
        }
    }
}

private enum ResizeCursorFactory {
    static let northwestSoutheast = makeCursor(northwestToSoutheast: true)
    static let northeastSouthwest = makeCursor(northwestToSoutheast: false)

    private static func makeCursor(northwestToSoutheast: Bool) -> NSCursor {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.white.withAlphaComponent(0.9).setStroke()
            let halo = diagonalPath(in: rect, northwestToSoutheast: northwestToSoutheast)
            halo.lineWidth = 4
            halo.stroke()

            NSColor.black.setStroke()
            let line = diagonalPath(in: rect, northwestToSoutheast: northwestToSoutheast)
            line.lineWidth = 1.5
            line.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 9, y: 9))
    }

    private static func diagonalPath(in rect: NSRect, northwestToSoutheast: Bool) -> NSBezierPath {
        let path = NSBezierPath()
        let a = northwestToSoutheast ? NSPoint(x: 3, y: 15) : NSPoint(x: 3, y: 3)
        let b = northwestToSoutheast ? NSPoint(x: 15, y: 3) : NSPoint(x: 15, y: 15)
        path.move(to: a)
        path.line(to: b)

        let sign: CGFloat = northwestToSoutheast ? -1 : 1
        path.move(to: a)
        path.line(to: NSPoint(x: a.x, y: a.y + sign * 5))
        path.move(to: a)
        path.line(to: NSPoint(x: a.x + 5, y: a.y))
        path.move(to: b)
        path.line(to: NSPoint(x: b.x, y: b.y - sign * 5))
        path.move(to: b)
        path.line(to: NSPoint(x: b.x - 5, y: b.y))
        return path
    }
}

final class SelectionSizeView: NSView {
    var text = "" { didSet { needsDisplay = true } }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
        NSColor.black.withAlphaComponent(0.78).setFill()
        background.fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
            withAttributes: attributes
        )
    }
}
