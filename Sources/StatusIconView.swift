import AppKit
import QuartzCore

/// WindowServer animates the circle independently of status queries and menu tracking.
final class StatusIconView: NSView {
    private let outer = CALayer()
    private let trackLeft = CAShapeLayer()
    private let battery = CAShapeLayer()
    private let trackRight = CAShapeLayer()
    private let volume = CAShapeLayer()
    private let sweep = CAShapeLayer()
    private let center = CALayer()
    private let dots = (0..<StatusGlyph.allCases.count).map { _ in CAShapeLayer() }
    private var status: SystemStatus?
    private var dotLayout = DotLayout()
    private var reducedMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.addSublayer(outer)
        layer?.addSublayer(center)
        // One arc, one layer: a shared path would mix both segments in strokeStart/strokeEnd.
        for shape in [trackLeft, battery, trackRight, volume, sweep] {
            shape.frame = NSRect(origin: .zero, size: DuoIcon.size)
            shape.fillColor = nil
            shape.lineWidth = DuoIcon.strokeWidth
            shape.lineCap = .round
            shape.strokeStart = 0
            shape.strokeEnd = 1
            outer.addSublayer(shape)
        }
        sweep.opacity = 0
        dots.forEach { outer.addSublayer($0) }
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let frame = NSRect(x: bounds.midX-DuoIcon.size.width/2, y: bounds.midY-DuoIcon.size.height/2,
                           width: DuoIcon.size.width, height: DuoIcon.size.height)
        outer.frame = frame; center.frame = frame
        CATransaction.commit()
    }
    override func viewDidChangeEffectiveAppearance() { refreshAppearance() }
    override func viewDidChangeBackingProperties() { refreshAppearance() }
    private func refreshAppearance() {
        guard let status else { return }
        render(status, animated: false)
    }

    func update(_ value: SystemStatus, layout: DotLayout = DotLayout()) {
        let old = status
        let layoutChanged = layout.visible != dotLayout.visible
        guard old != value || layoutChanged else { return }
        status = value; dotLayout = layout
        render(value, animated: old != nil && !reducedMotion)
        if let old, value.shouldAnimate(from: old) { animateTurn() }
        if let old, !old.battery.connectedToPower && value.battery.connectedToPower { animateCharging() }
        if !value.battery.connectedToPower { sweep.removeAllAnimations(); sweep.opacity = 0 }
    }

    private func render(_ value: SystemStatus, animated: Bool) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let color = NSColor.labelColor.usingColorSpace(.deviceRGB) ?? .black
            let charging: CGFloat = value.battery.connectedToPower ? 1 : 0
            let ring = DuoIcon.ringColor(status: value, base: color, charging: charging)
            let level = DuoIcon.volumeColor(base: color)
            let visible = dotLayout.visible
            let geometry = DuoIcon.RingGeometry(dotCount: visible.count)
            let leftPath = DuoIcon.arcPath(from: geometry.leftStart, to: geometry.leftEnd)
            let rightPath = DuoIcon.arcPath(from: geometry.rightStart, to: geometry.rightEnd)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            trackLeft.path = leftPath; battery.path = leftPath
            trackRight.path = rightPath; volume.path = rightPath
            sweep.path = leftPath
            transition(trackLeft, "strokeColor", to: ring.withAlphaComponent(0.20).cgColor, animated: animated)
            transition(battery, "strokeColor", to: ring.cgColor, animated: animated)
            transition(trackRight, "strokeColor", to: level.withAlphaComponent(0.20).cgColor, animated: animated)
            transition(volume, "strokeColor", to: level.cgColor, animated: animated)
            transition(battery, "strokeEnd", to: CGFloat(value.battery.percent ?? 0)/100, animated: animated)
            let outputLevel = value.audio.muted == true ? 0 : (value.audio.volume ?? 0)
            transition(volume, "strokeEnd", to: CGFloat(outputLevel)/100, animated: animated)
            sweep.strokeColor = ring.blended(withFraction: 0.7, of: .white)?.cgColor
            for (index, dot) in dots.enumerated() {
                dot.isHidden = index >= visible.count
                guard index < visible.count else { continue }
                let angle = (270 + (CGFloat(index)-CGFloat(visible.count-1)/2)*DuoIcon.dotPitch) * .pi/180
                let point = CGPoint(x: DuoIcon.center.x+DuoIcon.radius*cos(angle),
                                    y: DuoIcon.center.y+DuoIcon.radius*sin(angle))
                let diameter = DuoIcon.dotDiameter
                dot.path = CGPath(ellipseIn: CGRect(x: point.x-diameter/2, y: point.y-diameter/2,
                                                   width: diameter, height: diameter), transform: nil)
                dot.fillColor = color.cgColor
                transition(dot, "opacity", to: visible[index].isActive(in: value) ? Float(1) : Float(0.50), animated: animated)
            }
            let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(DuoIcon.size.width*scale), pixelsHigh: Int(DuoIcon.size.height*scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = DuoIcon.size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            DuoIcon.draw(status: value, layout: dotLayout, in: NSRect(origin: .zero, size: DuoIcon.size), color: color, components: .center)
            NSGraphicsContext.restoreGraphicsState()
            if animated {
                let fade = CATransition(); fade.type = .fade; fade.duration = 0.24
                center.add(fade, forKey: "state")
            }
            center.contentsScale = scale; center.contents = rep.cgImage
            CATransaction.commit()
        }
    }

    private func transition(_ layer: CALayer, _ key: String, to value: Any, animated: Bool) {
        let previous = layer.presentation()?.value(forKeyPath: key) ?? layer.value(forKeyPath: key)
        layer.setValue(value, forKeyPath: key)
        guard animated else { layer.removeAnimation(forKey: key); return }
        let animation = CABasicAnimation(keyPath: key)
        animation.fromValue = previous; animation.toValue = value
        animation.duration = 0.32
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: key)
    }

    func animateTurn() {
        guard !reducedMotion else { stopAnimations(); return }
        // Rapid changes and opening the menu join the current turn instead of restarting it.
        guard outer.animation(forKey: "turn") == nil else { return }
        let turn = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        let samples = 180
        turn.values = (0...samples).map { IconTurn.angle(at: IconTurn.duration * Double($0)/Double(samples)) }
        turn.keyTimes = (0...samples).map { NSNumber(value: Double($0)/Double(samples)) }
        turn.duration = IconTurn.duration
        turn.calculationMode = .linear
        outer.add(turn, forKey: "turn")
    }

    private func animateCharging() {
        guard !reducedMotion else { return }
        // The sweep rides the left (battery) arc, so its fraction keeps the old meaning.
        let percent = CGFloat(status?.battery.percent ?? 0)/100
        let end = CABasicAnimation(keyPath: "strokeEnd")
        end.fromValue = 0; end.toValue = percent
        let start = CABasicAnimation(keyPath: "strokeStart")
        start.fromValue = -0.09; start.toValue = max(0, percent-0.09)
        let glow = CAKeyframeAnimation(keyPath: "opacity")
        glow.values = [0, 0.8, 0]; glow.keyTimes = [0, 0.5, 1]
        let group = CAAnimationGroup(); group.animations = [start, end, glow]; group.duration = 1.05
        sweep.add(group, forKey: "charging")
    }
    func stopAnimations() {
        ([outer, center, trackLeft, battery, trackRight, volume, sweep] + dots).forEach { $0.removeAllAnimations() }
    }
}
