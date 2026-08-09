import AppKit
import ApplicationServices

struct ResolvedAXWindow {
    let element: AXUIElement
    let processID: pid_t
    let initialAXFrame: CGRect
}

enum AXAccess {
    static func copyAttribute(_ element: AXUIElement, _ attribute: CFString) -> (AXError, CFTypeRef?) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        return (error, value)
    }

    static func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        let (error, value) = copyAttribute(element, attribute)
        guard error == .success else { return nil }
        return value as? String
    }

    static func boolAttribute(_ element: AXUIElement, _ attribute: CFString) -> Bool? {
        let (error, value) = copyAttribute(element, attribute)
        guard error == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    static func elementAttribute(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        let (error, value) = copyAttribute(element, attribute)
        guard error == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    static func pointAttribute(_ element: AXUIElement, _ attribute: CFString) -> CGPoint? {
        let (error, value) = copyAttribute(element, attribute)
        guard error == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var point = CGPoint.zero
        let axValue = unsafeBitCast(value, to: AXValue.self)
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    static func sizeAttribute(_ element: AXUIElement, _ attribute: CFString) -> CGSize? {
        let (error, value) = copyAttribute(element, attribute)
        guard error == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var size = CGSize.zero
        let axValue = unsafeBitCast(value, to: AXValue.self)
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = pointAttribute(element, kAXPositionAttribute as CFString),
              let size = sizeAttribute(element, kAXSizeAttribute as CFString),
              size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0 else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    static func isSettable(_ element: AXUIElement, _ attribute: CFString) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute, &settable) == .success && settable.boolValue
    }
}

@MainActor
final class AXWindowResolver {
    private let excludedBundleIdentifiers: Set<String> = [
        "com.apple.dock",
        "com.apple.SystemUIServer",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.loginwindow"
    ]

    func resolveWindow(at appKitPoint: CGPoint) -> ResolvedAXWindow? {
        guard AXIsProcessTrusted(), let primaryFrame = NSScreen.screens.first?.frame else {
            return nil
        }

        let axPoint = ScreenCoordinateConverter(primaryScreenFrame: primaryFrame).appKitPointToAX(appKitPoint)
        var hitElement: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(
            AXUIElementCreateSystemWide(),
            Float(axPoint.x),
            Float(axPoint.y),
            &hitElement
        )
        guard error == .success, let hitElement else { return nil }

        var processID: pid_t = 0
        guard AXUIElementGetPid(hitElement, &processID) == .success,
              processID != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }

        if let bundleID = NSRunningApplication(processIdentifier: processID)?.bundleIdentifier,
           excludedBundleIdentifiers.contains(bundleID) {
            return nil
        }

        // CGWindow metadata is consulted once at mouseDown only. Excluding desktop
        // elements prevents Finder's desktop window from being treated as a target;
        // no pixels, window image, title, or content are requested.
        guard frontmostRegularWindowOwner(at: axPoint) == processID else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(appElement, 0.25)

        guard let window = owningWindow(startingAt: hitElement),
              isEligible(window: window, processID: processID),
              let frame = AXAccess.frame(of: window) else {
            return nil
        }

        return ResolvedAXWindow(element: window, processID: processID, initialAXFrame: frame)
    }

    func frame(of window: ResolvedAXWindow) -> CGRect? {
        guard isProcessStillRunning(window.processID) else { return nil }
        return AXAccess.frame(of: window.element)
    }

    func isStillEligible(_ window: ResolvedAXWindow) -> Bool {
        isProcessStillRunning(window.processID) && isEligible(window: window.element, processID: window.processID)
    }

    private func owningWindow(startingAt element: AXUIElement) -> AXUIElement? {
        if AXAccess.stringAttribute(element, kAXRoleAttribute as CFString) == (kAXWindowRole as String) {
            return element
        }
        if let window = AXAccess.elementAttribute(element, kAXWindowAttribute as CFString) {
            return window
        }

        var current = element
        for _ in 0..<8 {
            guard let parent = AXAccess.elementAttribute(current, kAXParentAttribute as CFString) else {
                return nil
            }
            if AXAccess.stringAttribute(parent, kAXRoleAttribute as CFString) == (kAXWindowRole as String) {
                return parent
            }
            current = parent
        }
        return nil
    }

    private func isEligible(window: AXUIElement, processID: pid_t) -> Bool {
        guard processID != ProcessInfo.processInfo.processIdentifier,
              AXAccess.stringAttribute(window, kAXRoleAttribute as CFString) == (kAXWindowRole as String),
              AXAccess.stringAttribute(window, kAXSubroleAttribute as CFString) == (kAXStandardWindowSubrole as String),
              AXAccess.boolAttribute(window, kAXMinimizedAttribute as CFString) != true,
              AXAccess.boolAttribute(window, "AXFullScreen" as CFString) != true,
              AXAccess.isSettable(window, kAXPositionAttribute as CFString),
              AXAccess.isSettable(window, kAXSizeAttribute as CFString),
              let frame = AXAccess.frame(of: window),
              frame.width >= 80,
              frame.height >= 50 else {
            return false
        }
        return true
    }

    private func isProcessStillRunning(_ processID: pid_t) -> Bool {
        NSRunningApplication(processIdentifier: processID)?.isTerminated == false
    }

    private func frontmostRegularWindowOwner(at axPoint: CGPoint) -> pid_t? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for window in windows {
            guard (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let owner = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let boundsDictionary = window[kCGWindowBounds as String] as? [String: Any],
                  let x = (boundsDictionary["X"] as? NSNumber)?.doubleValue,
                  let y = (boundsDictionary["Y"] as? NSNumber)?.doubleValue,
                  let width = (boundsDictionary["Width"] as? NSNumber)?.doubleValue,
                  let height = (boundsDictionary["Height"] as? NSNumber)?.doubleValue else {
                continue
            }
            let bounds = CGRect(x: x, y: y, width: width, height: height)

            // The small expansion includes AppKit resize borders and corners that
            // can sit just outside the Core Graphics content bounds.
            if bounds.insetBy(dx: -6, dy: -6).contains(axPoint) {
                return owner
            }
        }
        return nil
    }
}
