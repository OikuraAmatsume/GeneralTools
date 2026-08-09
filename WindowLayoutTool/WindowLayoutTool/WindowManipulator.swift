import AppKit
import ApplicationServices

@MainActor
final class WindowManipulator {
    @discardableResult
    func apply(
        appKitFrame: CGRect,
        to window: ResolvedAXWindow,
        primaryScreenFrame: CGRect
    ) -> Bool {
        guard AXIsProcessTrusted(),
              AXAccess.isSettable(window.element, kAXPositionAttribute as CFString),
              AXAccess.isSettable(window.element, kAXSizeAttribute as CFString) else {
            return false
        }

        let converter = ScreenCoordinateConverter(primaryScreenFrame: primaryScreenFrame)
        let axFrame = converter.appKitRectToAX(appKitFrame)
        var size = axFrame.size
        var position = axFrame.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size),
              let positionValue = AXValueCreate(.cgPoint, &position) else {
            return false
        }

        let sizeError = AXUIElementSetAttributeValue(
            window.element,
            kAXSizeAttribute as CFString,
            sizeValue
        )
        guard sizeError == .success else { return false }

        let positionError = AXUIElementSetAttributeValue(
            window.element,
            kAXPositionAttribute as CFString,
            positionValue
        )
        guard positionError == .success else { return false }

        // One delayed read is a lightweight verification only. Apps may enforce their
        // own minimum size; their final frame is accepted and never retried.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            _ = AXAccess.frame(of: window.element)
        }
        return true
    }
}
