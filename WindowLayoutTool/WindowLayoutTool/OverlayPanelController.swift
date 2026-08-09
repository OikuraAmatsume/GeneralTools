import AppKit

private final class NonActivatingOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayPanelController {
    private let panel: NSPanel
    private let layoutView: OverlayLayoutView
    private var animationGeneration = 0
    private(set) var targetScreenFrame: CGRect?

    init(layouts: [LayoutDefinition]) {
        let size = OverlayGeometry.panelSize(layoutCount: layouts.count)
        layoutView = OverlayLayoutView(layouts: layouts)
        panel = NonActivatingOverlayPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = layoutView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.setAccessibilityElement(false)
        panel.alphaValue = 0
    }

    var isVisible: Bool { panel.isVisible }

    func show(on screen: NSScreen) {
        position(on: screen)
        animationGeneration += 1
        let generation = animationGeneration
        panel.orderFrontRegardless()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.animationGeneration == generation else { return }
            }
        }
    }

    func moveIfNeeded(to screen: NSScreen) {
        guard targetScreenFrame != screen.frame else { return }
        position(on: screen)
    }

    func selection(atScreenPoint point: CGPoint) -> LayoutSelection? {
        guard panel.isVisible, panel.frame.contains(point) else { return nil }
        let local = CGPoint(x: point.x - panel.frame.minX, y: point.y - panel.frame.minY)
        return OverlayGeometry.selection(at: local, in: layoutView.bounds, layouts: layoutView.layouts)
    }

    func setSelection(_ selection: LayoutSelection?) {
        layoutView.selected = selection
    }

    func hide(immediately: Bool = false) {
        animationGeneration += 1
        let generation = animationGeneration
        layoutView.selected = nil
        targetScreenFrame = nil

        if immediately || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || !panel.isVisible {
            panel.alphaValue = 0
            panel.orderOut(nil)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.animationGeneration == generation else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    private func position(on screen: NSScreen) {
        let visible = screen.visibleFrame
        let size = layoutView.frame.size
        let origin = CGPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + 22
        )
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        targetScreenFrame = screen.frame
        layoutView.needsDisplay = true
    }
}
