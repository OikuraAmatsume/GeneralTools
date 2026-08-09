import AppKit
import CoreGraphics

@MainActor
final class DragCoordinator {
    private struct Context {
        let window: ResolvedAXWindow
        let initialMouse: CGPoint
    }

    private let settings: SettingsStore
    private let permissions: PermissionController
    private let overlay: OverlayPanelController
    private let layouts: [LayoutDefinition]
    private let resolver = AXWindowResolver()
    private let manipulator = WindowManipulator()

    private var monitor: GlobalDragMonitor?
    private var stateMachine = DragStateMachine()
    private var context: Context?
    private var watchdog: Timer?
    private var activeSince: TimeInterval = 0
    private var lastHoverUpdate: TimeInterval = 0
    private var lastFrameCheck: TimeInterval = 0

    init(
        settings: SettingsStore,
        permissions: PermissionController,
        overlay: OverlayPanelController,
        layouts: [LayoutDefinition]
    ) {
        self.settings = settings
        self.permissions = permissions
        self.overlay = overlay
        self.layouts = layouts
    }

    func start() {
        guard monitor == nil else { return }
        let monitor = GlobalDragMonitor(
            onMouseDown: { [weak self] in self?.mouseDown(at: $0) },
            onMouseDragged: { [weak self] in self?.mouseDragged(to: $0) },
            onMouseUp: { [weak self] in self?.mouseUp(at: $0) },
            onEscape: { [weak self] in self?.escapePressed() }
        )
        self.monitor = monitor
        monitor.start()
    }

    func stop() {
        monitor?.stop()
        monitor = nil
        cancelCurrentDrag()
        overlay.hide(immediately: true)
    }

    func displayConfigurationChanged() {
        // Cancelling is safer than retaining a target NSScreen that may have been
        // disconnected. The next drag rebuilds all geometry from current screens.
        cancelCurrentDrag()
    }

    func cancelCurrentDrag() {
        switch stateMachine.phase {
        case .potentialDrag, .activeDrag, .hoveringLayout:
            _ = stateMachine.transition(.failure)
        case .idle, .commit, .cancel:
            break
        }
        finishCycle(immediately: true)
    }

    private func mouseDown(at point: CGPoint) {
        if stateMachine.phase != .idle { cancelCurrentDrag() }
        guard settings.monitoringEnabled,
              settings.layoutsEnabled,
              permissions.isTrusted,
              let window = resolver.resolveWindow(at: point) else {
            return
        }

        context = Context(window: window, initialMouse: point)
        _ = stateMachine.transition(.mouseDownOnWindow)
        lastFrameCheck = 0
    }

    private func mouseDragged(to point: CGPoint) {
        guard let context else { return }
        guard permissions.isTrusted else {
            cancelCurrentDrag()
            return
        }

        if stateMachine.phase == .potentialDrag {
            let distance = hypot(point.x - context.initialMouse.x, point.y - context.initialMouse.y)
            guard distance >= 7 else { return }

            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastFrameCheck >= (1.0 / 30.0) else { return }
            lastFrameCheck = now
            guard let currentFrame = resolver.frame(of: context.window) else {
                cancelCurrentDrag()
                return
            }
            guard frameChanged(from: context.window.initialAXFrame, to: currentFrame) else { return }

            guard let screen = screen(containing: point) else {
                cancelCurrentDrag()
                return
            }
            _ = stateMachine.transition(.windowMovementConfirmed)
            overlay.show(on: screen)
            startWatchdog()
            updateHover(at: point, force: true)
            return
        }

        switch stateMachine.phase {
        case .activeDrag, .hoveringLayout:
            updateHover(at: point, force: false)
        default:
            break
        }
    }

    private func mouseUp(at point: CGPoint) {
        guard let context else { return }

        switch stateMachine.phase {
        case .hoveringLayout(let selection):
            guard permissions.isTrusted,
                  resolver.isStillEligible(context.window),
                  overlay.selection(atScreenPoint: point) == selection,
                  let screen = screen(containing: point),
                  let region = LayoutEngine.region(for: selection, in: layouts),
                  let primaryFrame = NSScreen.screens.first?.frame else {
                _ = stateMachine.transition(.failure)
                finishCycle()
                return
            }
            let targetFrame = LayoutEngine.frame(for: region.normalizedFrame, in: screen.visibleFrame)
            if manipulator.apply(appKitFrame: targetFrame, to: context.window, primaryScreenFrame: primaryFrame) {
                _ = stateMachine.transition(.mouseUpWithSelection)
            } else {
                _ = stateMachine.transition(.failure)
            }
            finishCycle()

        case .potentialDrag, .activeDrag:
            _ = stateMachine.transition(.mouseUpWithoutSelection)
            finishCycle()

        case .idle, .commit, .cancel:
            finishCycle()
        }
    }

    private func escapePressed() {
        switch stateMachine.phase {
        case .potentialDrag, .activeDrag, .hoveringLayout:
            _ = stateMachine.transition(.escape)
            finishCycle()
        case .idle, .commit, .cancel:
            break
        }
    }

    private func updateHover(at point: CGPoint, force: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastHoverUpdate >= (1.0 / 30.0) else { return }
        lastHoverUpdate = now

        guard let screen = screen(containing: point) else {
            cancelCurrentDrag()
            return
        }
        overlay.moveIfNeeded(to: screen)
        let selection = overlay.selection(atScreenPoint: point)
        overlay.setSelection(selection)

        if let selection {
            _ = stateMachine.transition(.hover(selection))
        } else if case .hoveringLayout = stateMachine.phase {
            _ = stateMachine.transition(.hoverCleared)
        }
    }

    private func startWatchdog() {
        watchdog?.invalidate()
        activeSince = ProcessInfo.processInfo.systemUptime
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else {
                    timer.invalidate()
                    return
                }
                let elapsed = ProcessInfo.processInfo.systemUptime - self.activeSince
                let buttonIsDown = CGEventSource.buttonState(.combinedSessionState, button: .left)
                if !buttonIsDown || elapsed > 60 {
                    self.cancelCurrentDrag()
                }
            }
        }
        timer.tolerance = 0.15
        watchdog = timer
    }

    private func finishCycle(immediately: Bool = false) {
        watchdog?.invalidate()
        watchdog = nil
        overlay.hide(immediately: immediately)
        context = nil
        lastHoverUpdate = 0
        lastFrameCheck = 0

        if stateMachine.phase != .idle {
            if stateMachine.phase != .commit && stateMachine.phase != .cancel {
                _ = stateMachine.transition(.failure)
            }
            _ = stateMachine.transition(.reset)
        }
    }

    private func frameChanged(from initial: CGRect, to current: CGRect) -> Bool {
        let tolerance: CGFloat = 0.75
        return abs(initial.minX - current.minX) > tolerance
            || abs(initial.minY - current.minY) > tolerance
            || abs(initial.width - current.width) > tolerance
            || abs(initial.height - current.height) > tolerance
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })
    }
}
