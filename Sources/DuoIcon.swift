import AppKit

/// Vector renderer shared by the menu item and its live settings icon.
enum DuoIcon {
    static let size = NSSize(width: 32, height: 28)
    static let outerDiameter: CGFloat = 26
    static let strokeWidth: CGFloat = 2.47
    static let dotDiameter: CGFloat = 3.12
    static let radius: CGFloat = (outerDiameter - strokeWidth) / 2
    static let center = NSPoint(x: size.width / 2, y: size.height / 2)
    static let dotPitch: CGFloat = 20
    static let lowBatteryThreshold = 20

    /// The ring is split in two mirrored arcs: battery on the left, volume on the right.
    /// The bottom gap widens with the visible dot count so the dots never touch an arc.
    struct RingGeometry {
        static let topGapHalf: CGFloat = 8
        static let bottomMargin: CGFloat = 10
        let dotCount: Int

        init(dotCount: Int) { self.dotCount = dotCount }

        var halfSpan: CGFloat { dotCount <= 1 ? 9 : CGFloat(dotCount - 1) * 10 + 9 }
        // Left arc runs from the lower left up to the upper left (clockwise, through 180 degrees).
        var leftStart: CGFloat { 270 - halfSpan - Self.bottomMargin }
        var leftEnd: CGFloat { 90 + Self.topGapHalf }
        // Right arc runs from the lower right up to the upper right (counter-clockwise, through 0).
        // The end deliberately exceeds 360 so the fill fraction grows monotonically.
        var rightStart: CGFloat { 270 + halfSpan + Self.bottomMargin }
        var rightEnd: CGFloat { 450 - Self.topGapHalf }

        func leftFill(_ fraction: CGFloat) -> CGFloat { leftStart + (leftEnd - leftStart) * clamp(fraction) }
        func rightFill(_ fraction: CGFloat) -> CGFloat { rightStart + (rightEnd - rightStart) * clamp(fraction) }
        private func clamp(_ value: CGFloat) -> CGFloat { max(0, min(1, value)) }
        var bottomGap: CGFloat { 2 * (halfSpan + Self.bottomMargin) }
    }

    static let chargingGreen = NSColor(calibratedRed: 0.18, green: 0.80, blue: 0.38, alpha: 1)
    static let lowBatteryRed = NSColor(calibratedRed: 0.95, green: 0.23, blue: 0.19, alpha: 1)

    /// Below 20 percent and running on battery: the only state that overrides the usual colours.
    static func isLowBattery(_ battery: BatteryState) -> Bool {
        guard battery.present, let percent = battery.percent else { return false }
        return percent < lowBatteryThreshold && !battery.connectedToPower
    }

    /// Single source of truth for the battery arc colour. Charging keeps the author's yellow
    /// low power override; the red warning sits above both because it is the urgent case.
    static func ringColor(status: SystemStatus, base: NSColor, charging: CGFloat) -> NSColor {
        if isLowBattery(status.battery) { return lowBatteryRed }
        if status.battery.lowPowerMode { return .systemYellow }
        if status.battery.connectedToPower {
            return base.blended(withFraction: charging, of: chargingGreen) ?? chargingGreen
        }
        return base
    }

    static func volumeColor(base: NSColor) -> NSColor { base }

    /// Readable role for `--diagnose`; mirrors `ringColor` without exposing NSColor.
    static func ringRole(status: SystemStatus) -> String {
        if isLowBattery(status.battery) { return "red" }
        if status.battery.lowPowerMode { return "yellow" }
        if status.battery.connectedToPower { return "green" }
        return "label"
    }

    /// One arc, one path: a shared path would let `strokeEnd` mix both segments.
    static func arcPath(from: CGFloat, to: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addArc(center: center, radius: radius, startAngle: from * .pi / 180,
                    endAngle: to * .pi / 180, clockwise: to < from)
        return path
    }

    static func image(status: SystemStatus, layout: DotLayout = DotLayout(), template: Bool = true) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            draw(status: status, layout: layout, in: rect, color: .black)
            return true
        }
        // A template image is recoloured by the system, which would erase the warning colours.
        image.isTemplate = template && !status.battery.connectedToPower && !status.battery.lowPowerMode
            && !isLowBattery(status.battery)
        return image
    }

    enum Components { case all, center }

    static func draw(status: SystemStatus, layout: DotLayout = DotLayout(), presentation: IconFrame? = nil, in rect: NSRect, color: NSColor, components: Components = .all) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        let scale = min(rect.width / size.width, rect.height / size.height)
        ctx.translateBy(x: rect.midX - size.width * scale / 2, y: rect.midY - size.height * scale / 2)
        ctx.scaleBy(x: scale, y: scale)
        let dots = layout.visible
        let frame = presentation ?? .steady(status)
        let strokeWidth = Self.strokeWidth
        let center = Self.center
        let radius = Self.radius
        let geometry = RingGeometry(dotCount: dots.count)
        let base = color.usingColorSpace(.deviceRGB) ?? color
        let ringStroke = Self.ringColor(status: status, base: base, charging: frame.charging)
        let volumeStroke = Self.volumeColor(base: base)
        if components == .all {
            ctx.saveGState()
            ctx.translateBy(x: center.x, y: center.y); ctx.rotate(by: frame.ringAngle)
            ctx.translateBy(x: -center.x, y: -center.y)
            func arc(_ from: CGFloat, _ to: CGFloat, _ color: NSColor, alpha: CGFloat) {
                color.withAlphaComponent(alpha).setStroke()
                let path = NSBezierPath()
                path.lineWidth = strokeWidth
                path.lineCapStyle = .round
                path.appendArc(withCenter: center, radius: radius, startAngle: from,
                               endAngle: to, clockwise: to < from)
                path.stroke()
            }
            // Tracks first, then the two independent fills.
            arc(geometry.leftStart, geometry.leftEnd, ringStroke, alpha: 0.20)
            arc(geometry.rightStart, geometry.rightEnd, volumeStroke, alpha: 0.20)
            if let percent = frame.percent, percent > 0 {
                arc(geometry.leftStart, geometry.leftFill(percent / 100), ringStroke, alpha: 1)
            }
            if let volume = frame.volume, volume > 0 {
                arc(geometry.rightStart, geometry.rightFill(volume / 100), volumeStroke, alpha: 1)
            }
            if let phase = frame.chargeSweep, let percent = frame.percent {
                let sweep = geometry.leftEnd - geometry.leftStart
                let end = geometry.leftStart + sweep * percent / 100 * phase
                let path = NSBezierPath(); path.lineWidth = strokeWidth; path.lineCapStyle = .round
                ringStroke.blended(withFraction: 0.7, of: .white)?.withAlphaComponent(sin(.pi*phase)*0.8).setStroke()
                path.appendArc(withCenter: center, radius: radius, startAngle: min(geometry.leftStart, end+22),
                               endAngle: end, clockwise: true)
                path.stroke()
            }
            ctx.restoreGState()
        }
        if let old = frame.previousWiFi, frame.wifiBlend < 1 {
            ctx.saveGState(); ctx.setAlpha(1-frame.wifiBlend)
            drawWiFi(old, in: NSRect(x: 10.1, y: 11, width: 11.8, height: 8), color: color)
            ctx.restoreGState()
        }
        ctx.saveGState(); ctx.setAlpha(frame.wifiBlend)
        drawWiFi(status.wifi, in: NSRect(x: 10.1, y: 11, width: 11.8, height: 8), color: color)
        ctx.restoreGState()
        // Equal-sized dots: only opacity changes with the state.
        if components == .all {
            for (index, glyph) in dots.enumerated() {
                let active = frame.active[glyph] ?? 0
                let diameter = Self.dotDiameter
                color.withAlphaComponent(0.50 + 0.50*active).setFill()
                let angle = (270 + (CGFloat(index) - CGFloat(dots.count - 1) / 2) * dotPitch) * .pi / 180 + frame.ringAngle
                let point = NSPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
                NSBezierPath(ovalIn: NSRect(x: point.x - diameter / 2, y: point.y - diameter / 2,
                                           width: diameter, height: diameter)).fill()
            }
        }
        ctx.restoreGState()
    }

    private static func drawWiFi(_ wifi: WiFiState, in rect: NSRect, color: NSColor) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: rect.midX, y: rect.midY)
        context.scaleBy(x: 1.15, y: 1.15)
        context.translateBy(x: -rect.midX, y: -rect.midY)
        guard wifi.associated || wifi.route != .ethernet else {
            drawSymbol("network", in: rect, color: color); return
        }
        let origin = NSPoint(x: rect.midX, y: rect.minY + 0.6)
        let strengths = wifi.signalLevel
        for level in 1...2 {
            let path = NSBezierPath()
            path.lineWidth = 1.45; path.lineCapStyle = .round
            color.withAlphaComponent(wifi.associated && level < strengths ? 1 : 0.25).setStroke()
            path.appendArc(withCenter: origin, radius: CGFloat(level) * 3.2,
                           startAngle: 46, endAngle: 134, clockwise: false)
            path.stroke()
        }
        color.withAlphaComponent(wifi.associated ? 1 : 0.3).setFill()
        let dot = NSBezierPath()
        dot.move(to: NSPoint(x: origin.x - 0.95, y: origin.y + 0.6))
        dot.curve(to: NSPoint(x: origin.x + 0.95, y: origin.y + 0.6),
                  controlPoint1: NSPoint(x: origin.x - 0.8, y: origin.y + 1.4),
                  controlPoint2: NSPoint(x: origin.x + 0.8, y: origin.y + 1.4))
        dot.curve(to: NSPoint(x: origin.x, y: origin.y - 0.6),
                  controlPoint1: NSPoint(x: origin.x + 1.6, y: origin.y + 0.3),
                  controlPoint2: NSPoint(x: origin.x + 0.6, y: origin.y - 0.4))
        dot.curve(to: NSPoint(x: origin.x - 0.95, y: origin.y + 0.6),
                  controlPoint1: NSPoint(x: origin.x - 0.35, y: origin.y - 0.8),
                  controlPoint2: NSPoint(x: origin.x - 1.5, y: origin.y + 0.1))
        dot.close(); dot.fill()
        if !wifi.associated {
            let path = NSBezierPath(); path.lineWidth = 1.25; path.lineCapStyle = .round
            color.setStroke()
            path.move(to: NSPoint(x: rect.minX + 2, y: rect.maxY - 0.5))
            path.line(to: NSPoint(x: rect.maxX - 1.5, y: rect.minY))
            path.stroke()
        }
    }

    static func drawSymbol(_ name: String, in rect: NSRect, color: NSColor) {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: rect.height, weight: .semibold)) else { return }
        let ratio = min(rect.width / symbol.size.width, rect.height / symbol.size.height)
        let target = NSRect(x: rect.midX - symbol.size.width * ratio / 2,
                            y: rect.midY - symbol.size.height * ratio / 2,
                            width: symbol.size.width * ratio, height: symbol.size.height * ratio)
        let tinted = NSImage(size: symbol.size, flipped: false) { r in
            symbol.draw(in: r)
            color.setFill(); r.fill(using: .sourceIn)
            return true
        }
        tinted.draw(in: target)
    }
}
