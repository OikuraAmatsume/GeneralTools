import AppKit

@MainActor
final class OverlayLayoutView: NSView {
    let layouts: [LayoutDefinition]
    var selected: LayoutSelection? {
        didSet {
            if oldValue != selected { needsDisplay = true }
        }
    }

    init(layouts: [LayoutDefinition]) {
        self.layouts = layouts
        super.init(frame: CGRect(origin: .zero, size: OverlayGeometry.panelSize(layoutCount: layouts.count)))
        wantsLayer = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let background = reduceTransparency
            ? NSColor(calibratedWhite: 0.12, alpha: 1)
            : NSColor(calibratedWhite: 0.08, alpha: 0.84)
        background.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill()

        let hitRegions = OverlayGeometry.hitRegions(in: bounds, layouts: layouts)
        for (index, layout) in layouts.enumerated() {
            let card = OverlayGeometry.cardFrame(index: index, bounds: bounds)
            NSColor(calibratedWhite: 1, alpha: 0.08).setFill()
            NSBezierPath(roundedRect: card, xRadius: 8, yRadius: 8).fill()

            let labelRect = CGRect(x: card.minX + 2, y: card.minY + 1, width: card.width - 4, height: OverlayGeometry.labelHeight - 1)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.88),
                .paragraphStyle: paragraph
            ]
            (layout.name as NSString).draw(in: labelRect, withAttributes: attributes)
        }

        for hit in hitRegions {
            let isSelected = hit.selection == selected
            (isSelected ? NSColor.systemBlue : NSColor.white.withAlphaComponent(0.86)).setFill()
            NSBezierPath(roundedRect: hit.frame, xRadius: 2.5, yRadius: 2.5).fill()

            if isSelected {
                NSColor.white.withAlphaComponent(0.75).setStroke()
                let outline = NSBezierPath(roundedRect: hit.frame.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2)
                outline.lineWidth = 1
                outline.stroke()
            }
        }
    }
}
