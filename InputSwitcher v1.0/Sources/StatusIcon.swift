import AppKit

enum StatusIcon {
    static func image(isActive: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            NSColor.labelColor.setStroke()
            NSColor.labelColor.setFill()

            for radius in [4.2, 7.0] {
                drawArc(center: center, radius: radius, startAngle: 35, endAngle: 145)
                drawArc(center: center, radius: radius, startAngle: 215, endAngle: 325)
            }

            let nodeRadius: CGFloat = 1.8
            let node = NSBezierPath(
                ovalIn: NSRect(
                    x: center.x - nodeRadius,
                    y: center.y - nodeRadius,
                    width: nodeRadius * 2,
                    height: nodeRadius * 2
                )
            )

            if isActive {
                node.fill()
            } else {
                node.lineWidth = 1.3
                node.stroke()
            }

            return true
        }

        image.isTemplate = true
        image.accessibilityDescription = "Amatsume init 监听状态"
        return image
    }

    private static func drawArc(
        center: NSPoint,
        radius: CGFloat,
        startAngle: CGFloat,
        endAngle: CGFloat
    ) {
        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle
        )
        arc.lineWidth = 1.45
        arc.lineCapStyle = .round
        arc.stroke()
    }
}
