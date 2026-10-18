import AppKit
import SatsumaCore

/// Borderless, non-activating panel above everything. The ring of wedges is one drop target for the ongoing
/// Finder drag; the wedge under the pointer is picked by angle.
final class WheelPanel: NSPanel {
    private let wheel = WheelView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
    private let glass = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
    private var generation = 0 // a stale fade-out must not hide a newer wheel

    init() {
        super.init(contentRect: wheel.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .transient, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.maskImage = NSImage(size: glass.frame.size, flipped: false) { rect in
            NSBezierPath(ovalIn: rect.insetBy(dx: 10, dy: 10)).fill()
            return true
        }
        glass.wantsLayer = true
        glass.addSubview(wheel)
        contentView = glass
    }

    func show(_ formats: [Format], at point: NSPoint, onPick: @escaping (Format) -> Void) {
        generation += 1
        wheel.configure(formats, onPick: onPick)
        setFrameOrigin(NSPoint(x: point.x - frame.width / 2, y: point.y - frame.height / 2))
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
        scaleIn()
    }

    func dismiss() {
        guard isVisible else { return }
        let current = generation
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.generation == current else { return }
            self.orderOut(nil)
        })
    }

    /// Springs the ring from 90% to full size around its centre.
    private func scaleIn() {
        guard let layer = glass.layer else { return }
        let c = CGPoint(x: glass.bounds.midX, y: glass.bounds.midY)
        var from = CATransform3DMakeTranslation(c.x, c.y, 0)
        from = CATransform3DScale(from, 0.9, 0.9, 1)
        from = CATransform3DTranslate(from, -c.x, -c.y, 0)
        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = from
        spring.toValue = CATransform3DIdentity
        spring.stiffness = 260
        spring.damping = 24 // near-critical: settles without a visible wobble
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "scale")
    }
}

final class WheelView: NSView {
    static let outer: CGFloat = 140, inner: CGFloat = 50
    private static let rimPad: CGFloat = 5, corner: CGFloat = 8, gap: CGFloat = 2.5, lift: CGFloat = 3

    private var formats: [Format] = []
    private var onPick: ((Format) -> Void)?
    /// Per-wedge hover amount 0…1, eased toward 1 for the hovered wedge and 0 for the rest.
    private var glow: [CGFloat] = []
    private var pill: CGFloat = 0
    private var pillLabel = ""
    private var animator: Timer?
    private var hot: Int? {
        didSet {
            guard hot != oldValue else { return }
            if let hot {
                pillLabel = formats[hot].label.uppercased()
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            startAnimating()
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(_ formats: [Format], onPick: @escaping (Format) -> Void) {
        self.formats = formats
        self.onPick = onPick
        glow = Array(repeating: 0, count: formats.count)
        pill = 0
        hot = nil
        needsDisplay = true
    }

    // MARK: Hover animation

    private func startAnimating() {
        guard animator == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.stepAnimation() }
        RunLoop.main.add(timer, forMode: .common)
        animator = timer
    }

    private func stepAnimation() {
        var settled = true
        func ease(_ value: inout CGFloat, to target: CGFloat) {
            value += (target - value) * 0.22 // exponential ease-out, ~150 ms to settle
            if abs(target - value) < 0.005 { value = target } else { settled = false }
        }
        for i in glow.indices { ease(&glow[i], to: i == hot ? 1 : 0) }
        ease(&pill, to: hot == nil ? 0 : 1)
        needsDisplay = true
        if settled { animator?.invalidate(); animator = nil }
    }

    // MARK: Geometry

    private var center: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }
    private var step: CGFloat { 2 * .pi / CGFloat(max(formats.count, 1)) }

    /// Wedge `i` is centred `i * step` clockwise from 12 o'clock.
    private func angle(_ i: Int) -> CGFloat { .pi / 2 - CGFloat(i) * step }

    func index(at p: NSPoint) -> Int? {
        let dx = p.x - center.x, dy = p.y - center.y
        let d = hypot(dx, dy)
        guard !formats.isEmpty, d >= Self.inner, d <= Self.outer else { return nil }
        var a = atan2(dx, dy) // clockwise from 12 o'clock
        if a < 0 { a += 2 * .pi }
        return Int((a + step / 2) / step) % formats.count
    }

    /// Annular sector shrunk by `corner`; filling and stroking it with a round join gives rounded corners.
    /// `offset` slides it outward along its centre line.
    private func wedge(_ i: Int, offset: CGFloat) -> CGPath {
        let mid = angle(i), half = step / 2
        let c = CGPoint(x: center.x + offset * cos(mid), y: center.y + offset * sin(mid))
        let ro = Self.outer - Self.rimPad - Self.corner - Self.lift, ri = Self.inner + Self.corner
        let edge = Self.gap + Self.corner // keeps the gaps between wedges parallel
        let ao = half - edge / ro, ai = half - edge / ri
        let path = CGMutablePath()
        path.addArc(center: c, radius: ro, startAngle: mid + ao, endAngle: mid - ao, clockwise: true)
        path.addArc(center: c, radius: ri, startAngle: mid - ai, endAngle: mid + ai, clockwise: false)
        path.closeSubpath()
        return path
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let c = center
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let idleAlpha: CGFloat = dark ? 0.08 : 0.55
        // Smoked glass: dark tint on a light wheel, pale tint on a dark one.
        let smoke = dark ? [CGColor(gray: 1, alpha: 0.30), CGColor(gray: 1, alpha: 0.16)]
                         : [CGColor(gray: 0.06, alpha: 0.80), CGColor(gray: 0.16, alpha: 0.62)]
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.genericGrayGamma2_2),
                                  colors: smoke as CFArray, locations: [0, 1])!

        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(1)
        ctx.strokeEllipse(in: CGRect(x: c.x - Self.outer, y: c.y - Self.outer, width: 2 * Self.outer, height: 2 * Self.outer))

        for (i, format) in formats.enumerated() {
            let g = glow[i]
            let path = wedge(i, offset: Self.lift * g)

            fill(path, in: ctx, alpha: idleAlpha) { ctx.setFillColor(.white) }
            if g > 0 { // smoke fades in over the idle wedge
                fill(path, in: ctx, alpha: g) {
                    ctx.setBlendMode(.sourceIn)
                    let box = path.boundingBox.insetBy(dx: -Self.corner, dy: -Self.corner)
                    ctx.drawLinearGradient(gradient, start: CGPoint(x: box.midX, y: box.maxY),
                                           end: CGPoint(x: box.midX, y: box.minY), options: [])
                }
            }

            let r = (Self.outer - Self.rimPad - Self.lift + Self.inner) / 2 + Self.lift * g
            let p = CGPoint(x: c.x + r * cos(angle(i)), y: c.y + r * sin(angle(i)))
            let color = dark ? NSColor.labelColor : NSColor.labelColor.blended(withFraction: g, of: .white)!
            format.label.uppercased().drawCentered(at: p, font: .systemFont(ofSize: 12.5, weight: .semibold), color: color)
        }

        let hub = NSRect(x: c.x - Self.inner + 8, y: c.y - Self.inner + 8, width: 2 * (Self.inner - 8), height: 2 * (Self.inner - 8))
        NSColor.white.withAlphaComponent(idleAlpha).setFill()
        NSBezierPath(ovalIn: hub).fill()

        if pill > 0 {
            ctx.saveGState()
            ctx.setAlpha(pill)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            let rect = NSRect(x: c.x - 34, y: c.y - 13, width: 68, height: 26)
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 8
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
            shadow.set()
            NSColor.controlBackgroundColor.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 13, yRadius: 13).fill()
            NSShadow().set()
            pillLabel.drawCentered(at: c, font: .systemFont(ofSize: 10.5, weight: .semibold), color: .labelColor)
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        }
    }

    /// Draws the rounded wedge as one shape in a transparency layer, so `alpha` applies once
    /// (fill and stroke overlap) and `paint` can recolour it with `.sourceIn`.
    private func fill(_ path: CGPath, in ctx: CGContext, alpha: CGFloat, paint: () -> Void) {
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.addPath(path)
        ctx.setFillColor(.white)
        ctx.setStrokeColor(.white)
        ctx.setLineWidth(2 * Self.corner)
        ctx.setLineJoin(.round)
        ctx.drawPath(using: .fillStroke)
        paint()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    // MARK: Dropping

    private func track(_ sender: NSDraggingInfo) -> NSDragOperation {
        hot = index(at: convert(sender.draggingLocation, from: nil))
        return hot == nil ? [] : .copy // .copy, never .move: the source file must stay put
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { track(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { track(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { hot = nil }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { hot != nil }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let hot, let onPick else { return false }
        let format = formats[hot]
        // Async: let the drop finish before anything else runs.
        DispatchQueue.main.async { onPick(format) }
        return true
    }
}

private extension String {
    func drawCentered(at point: CGPoint, font: NSFont, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (self as NSString).size(withAttributes: attrs)
        (self as NSString).draw(at: NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2),
                                withAttributes: attrs)
    }
}
