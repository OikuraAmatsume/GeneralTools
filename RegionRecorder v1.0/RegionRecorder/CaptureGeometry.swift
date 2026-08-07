import AppKit
import CoreGraphics

struct CaptureRegionDescriptor: Equatable {
    let displayID: CGDirectDisplayID
    let screenFrame: CGRect
    let captureFrame: CGRect
    let backingScaleFactor: CGFloat
}

enum CaptureGeometry {
    static let minimumCaptureSize = CGSize(width: 160, height: 90)

    /// Converts an AppKit global rectangle (bottom-left origin) into the display-local,
    /// top-left-origin point coordinates expected by ScreenCaptureKit's sourceRect.
    static func sourceRect(captureFrame: CGRect, in screenFrame: CGRect) -> CGRect {
        CGRect(
            x: captureFrame.minX - screenFrame.minX,
            y: screenFrame.maxY - captureFrame.maxY,
            width: captureFrame.width,
            height: captureFrame.height
        )
    }

    /// ScreenCaptureKit accepts a point-based source rect and a pixel-based output size.
    /// H.264 dimensions are rounded to positive even values for broad player compatibility.
    static func outputPixelSize(
        captureSize: CGSize,
        backingScaleFactor: CGFloat,
        outputScale: CGFloat
    ) -> CGSize {
        func even(_ value: CGFloat) -> CGFloat {
            let rounded = max(2, Int((value / 2).rounded()) * 2)
            return CGFloat(rounded)
        }

        return CGSize(
            width: even(captureSize.width * backingScaleFactor * outputScale),
            height: even(captureSize.height * backingScaleFactor * outputScale)
        )
    }

    static func clamped(_ proposed: CGRect, to bounds: CGRect) -> CGRect {
        var result = proposed.standardized
        result.size.width = min(max(result.width, minimumCaptureSize.width), bounds.width)
        result.size.height = min(max(result.height, minimumCaptureSize.height), bounds.height)
        result.origin.x = min(max(result.minX, bounds.minX), bounds.maxX - result.width)
        result.origin.y = min(max(result.minY, bounds.minY), bounds.maxY - result.height)
        return result.integral
    }
}

extension NSScreen {
    var directDisplayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }
}
