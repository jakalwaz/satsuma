// Renders the 1024×1024 app icon PNG: a smoked-glass tile with the six-segment wheel.
// Usage: swift scripts/make-icon.swift out.png   (bundle.sh turns it into AppIcon.icns)
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    // macOS icon grid: 824 pt tile centred on a 1024 canvas, ~185 pt corner radius.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: NSColor(white: 0.27, alpha: 1), ending: NSColor(white: 0.07, alpha: 1))!.draw(in: shape, angle: -90)
    // Soft top sheen, like light on smoked glass.
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(starting: NSColor(white: 1, alpha: 0.16), ending: NSColor(white: 1, alpha: 0))!
        .draw(in: NSRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Six rounded segments; the top one is lit, the rest are frosted.
    let c = NSPoint(x: size / 2, y: size / 2)
    for i in 0..<6 {
        let mid = 90 - CGFloat(i) * 60 // segment i centred i·60° clockwise from 12 o'clock
        let arc = NSBezierPath()
        arc.appendArc(withCenter: c, radius: 245, startAngle: mid - 15, endAngle: mid + 15)
        arc.lineWidth = 84
        arc.lineCapStyle = .round
        NSColor.white.withAlphaComponent(i == 0 ? 1 : 0.42).setStroke()
        arc.stroke()
    }
    NSColor.white.withAlphaComponent(0.9).setFill()
    NSBezierPath(ovalIn: NSRect(x: c.x - 48, y: c.y - 48, width: 96, height: 96)).fill()
    return true
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
