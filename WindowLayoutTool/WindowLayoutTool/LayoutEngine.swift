import Foundation
import CoreGraphics

enum LayoutEngine {
    static func frame(for normalized: NormalizedRect, in visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: visibleFrame.minX + visibleFrame.width * normalized.x,
            y: visibleFrame.minY + visibleFrame.height * normalized.y,
            width: visibleFrame.width * normalized.width,
            height: visibleFrame.height * normalized.height
        )
    }

    static func region(for selection: LayoutSelection, in layouts: [LayoutDefinition]) -> LayoutRegion? {
        layouts.first(where: { $0.id == selection.layoutID })?
            .regions.first(where: { $0.id == selection.regionID })
    }
}

struct OverlayHitRegion: Equatable {
    let selection: LayoutSelection
    let frame: CGRect
}

enum OverlayGeometry {
    static let outerPadding: CGFloat = 14
    static let cardSpacing: CGFloat = 12
    static let cardWidth: CGFloat = 126
    static let previewHeight: CGFloat = 74
    static let labelHeight: CGFloat = 20
    static let cardHeight: CGFloat = previewHeight + labelHeight
    static let panelHeight: CGFloat = cardHeight + outerPadding * 2
    static let verticalCenterFraction: CGFloat = 1.0 / 3.0

    static func panelSize(layoutCount: Int) -> CGSize {
        let width = outerPadding * 2
            + CGFloat(layoutCount) * cardWidth
            + CGFloat(max(layoutCount - 1, 0)) * cardSpacing
        return CGSize(width: width, height: panelHeight)
    }

    static func panelOrigin(size: CGSize, in visibleFrame: CGRect) -> CGPoint {
        let desiredY = visibleFrame.minY
            + visibleFrame.height * verticalCenterFraction
            - size.height / 2
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - size.height)
        return CGPoint(
            x: visibleFrame.midX - size.width / 2,
            y: min(max(desiredY, visibleFrame.minY), maximumY)
        )
    }

    static func cardFrame(index: Int, bounds: CGRect) -> CGRect {
        CGRect(
            x: bounds.minX + outerPadding + CGFloat(index) * (cardWidth + cardSpacing),
            y: bounds.minY + outerPadding,
            width: cardWidth,
            height: cardHeight
        )
    }

    static func previewFrame(index: Int, bounds: CGRect) -> CGRect {
        let card = cardFrame(index: index, bounds: bounds)
        return CGRect(x: card.minX, y: card.minY + labelHeight, width: card.width, height: previewHeight)
            .insetBy(dx: 5, dy: 5)
    }

    static func hitRegions(in bounds: CGRect, layouts: [LayoutDefinition]) -> [OverlayHitRegion] {
        layouts.enumerated().flatMap { index, layout in
            let preview = previewFrame(index: index, bounds: bounds)
            return layout.regions.map { region in
                OverlayHitRegion(
                    selection: LayoutSelection(layoutID: layout.id, regionID: region.id),
                    frame: LayoutEngine.frame(for: region.normalizedFrame, in: preview).insetBy(dx: 1, dy: 1)
                )
            }
        }
    }

    static func selection(at point: CGPoint, in bounds: CGRect, layouts: [LayoutDefinition]) -> LayoutSelection? {
        hitRegions(in: bounds, layouts: layouts).first(where: { $0.frame.contains(point) })?.selection
    }
}
