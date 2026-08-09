import Foundation
import CoreGraphics

struct ScreenCoordinateConverter: Equatable {
    let primaryScreenFrame: CGRect

    func appKitPointToAX(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x - primaryScreenFrame.minX,
            y: primaryScreenFrame.maxY - point.y
        )
    }

    func axPointToAppKit(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x + primaryScreenFrame.minX,
            y: primaryScreenFrame.maxY - point.y
        )
    }

    func appKitRectToAX(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX - primaryScreenFrame.minX,
            y: primaryScreenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    func axRectToAppKit(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX + primaryScreenFrame.minX,
            y: primaryScreenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
