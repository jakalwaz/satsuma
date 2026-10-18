import AppKit

enum Logo {
    /// Six-segment ring, like the wheel. Template, so the menu bar tints it.
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let c = NSPoint(x: rect.midX, y: rect.midY)
            for i in 0..<6 {
                let start = CGFloat(i) * 60 + 90 + 9 // 18° gaps, first gap at 12 o'clock
                let arc = NSBezierPath()
                arc.appendArc(withCenter: c, radius: 6.5, startAngle: start, endAngle: start + 42)
                arc.lineWidth = 2.2
                arc.lineCapStyle = .round
                arc.stroke()
            }
            NSBezierPath(ovalIn: NSRect(x: c.x - 1.5, y: c.y - 1.5, width: 3, height: 3)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Satsuma"
        return image
    }

    static let ascii = """
     .-.-.
    ( -+- )  satsuma
     '-'-'
    """

    static func menuHeader() -> NSMenuItem {
        let item = NSMenuItem()
        item.attributedTitle = NSAttributedString(string: ascii, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        item.isEnabled = false
        return item
    }
}
