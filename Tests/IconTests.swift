import AppKit
import QuartzCore

@main
struct IconTests {
    static let scale: CGFloat = 10

    static func check(_ passed: Bool, _ text: String) {
        guard passed else { fputs("FAIL: \(text)\n", stderr); exit(1) }
    }

    static func state(percent: Int?, volume: Int?, charging: Bool = false, externalPower: Bool = false,
                      lowPower: Bool = false, dots: Set<StatusGlyph> = []) -> SystemStatus {
        var s = SystemStatus()
        s.wifi = WiFiState(available: true, powered: true, associated: true, ssid: "Home", rssi: -48, route: .wifi)
        s.battery = BatteryState(present: percent != nil, percent: percent, charging: charging,
                                 externalPower: externalPower || charging, minutesRemaining: nil,
                                 lowPowerMode: lowPower)
        s.audio = AudioState(outputName: "Built-in Output",
                             headphoneNames: dots.contains(.headphones) ? ["Headphones"] : [],
                             muted: dots.contains(.mute), volume: volume,
                             micInUse: dots.contains(.microphone))
        s.vpn.names = dots.contains(.vpn) ? ["Work VPN"] : []
        s.focus = dots.contains(.focus) ? .active : .off
        s.thermal = dots.contains(.thermal) ? .serious : .nominal
        return s
    }

    static func bitmap(_ status: SystemStatus, layout: DotLayout = DotLayout(), frame: IconFrame? = nil) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(DuoIcon.size.width*scale),
                                  pixelsHigh: Int(DuoIcon.size.height*scale), bitsPerSample: 8, samplesPerPixel: 4,
                                  hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = DuoIcon.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        DuoIcon.draw(status: status, layout: layout, presentation: frame,
                     in: NSRect(origin: .zero, size: DuoIcon.size), color: .black)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// Sample on the ring at a given angle; the bitmap is flipped, so y is mirrored back.
    static func pixel(_ rep: NSBitmapImageRep, angleDeg: Double, radius: Double = DuoIcon.radius) -> NSColor {
        let a = angleDeg * .pi / 180
        let x = DuoIcon.center.x + CGFloat(radius * cos(a))
        let y = DuoIcon.center.y + CGFloat(radius * sin(a))
        let px = min(rep.pixelsWide - 1, max(0, Int(x*scale)))
        let py = min(rep.pixelsHigh - 1, max(0, rep.pixelsHigh - 1 - Int(y*scale)))
        return rep.colorAt(x: px, y: py) ?? .clear
    }
    static func alpha(_ rep: NSBitmapImageRep, _ angleDeg: Double, radius: Double = DuoIcon.radius) -> Double {
        Double(pixel(rep, angleDeg: angleDeg, radius: radius).alphaComponent)
    }
    static func rgb(_ rep: NSBitmapImageRep, _ angleDeg: Double) -> (r: Double, g: Double, b: Double) {
        let c = pixel(rep, angleDeg: angleDeg).usingColorSpace(.deviceRGB) ?? .black
        return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
    }
    static func achromatic(_ color: NSColor) -> Bool {
        let c = color.usingColorSpace(.deviceRGB) ?? .black
        return abs(Double(c.redComponent) - Double(c.greenComponent)) < 0.2
            && abs(Double(c.greenComponent) - Double(c.blueComponent)) < 0.2
    }

    static func main() throws {
        _ = NSApplication.shared
        // Four visible dots: left arc 221 -> 98, right arc 319 -> 442.
        let geometry = DuoIcon.RingGeometry(dotCount: 4)
        check(abs(geometry.leftStart - 221) < 0.001 && abs(geometry.leftEnd - 98) < 0.001,
              "the left arc spans 221 to 98 degrees")
        check(abs(geometry.rightStart - 319) < 0.001 && abs(geometry.rightEnd - 442) < 0.001,
              "the right arc spans 319 to 442 degrees")
        check(abs(geometry.bottomGap - 98) < 0.001, "four dots reserve a 98 degree bottom gap")

        // The battery fills the left arc from the lower left upward.
        let full = bitmap(state(percent: 100, volume: 0))
        for angle in [200.0, 150.0, 110.0] {
            check(alpha(full, angle) > 0.9, "full battery lights the left arc at \(angle) degrees")
        }
        let emptyBattery = bitmap(state(percent: 0, volume: 0))
        for angle in [200.0, 150.0, 110.0] {
            check(alpha(emptyBattery, angle) < 0.3, "empty battery leaves only the track at \(angle) degrees")
        }
        let halfBattery = bitmap(state(percent: 50, volume: 0))
        check(alpha(halfBattery, 200) > 0.9, "half battery starts at the lower left")
        check(alpha(halfBattery, 150) < 0.3, "half battery stops before the upper left")

        // The volume fills the mirrored right arc, also from the bottom up.
        let fullVolume = bitmap(state(percent: 0, volume: 100))
        for angle in [340.0, 20.0, 78.0] {
            check(alpha(fullVolume, angle) > 0.9, "full volume lights the right arc at \(angle) degrees")
        }
        let emptyVolume = bitmap(state(percent: 0, volume: 0))
        for angle in [340.0, 20.0, 78.0] {
            check(alpha(emptyVolume, angle) < 0.3, "zero volume leaves only the track at \(angle) degrees")
        }
        let lowVolume = bitmap(state(percent: 0, volume: 40))
        check(alpha(lowVolume, 340) > 0.9, "40 percent volume fills the lower right")
        check(alpha(lowVolume, 20) < 0.3, "40 percent volume stops before the upper right")

        // Both arcs honour their own end points and leave both gaps empty.
        let both = bitmap(state(percent: 100, volume: 100))
        for angle in [218.0, 103.0, 325.0, 77.0] {
            check(alpha(both, angle) > 0.9, "filled arcs cover \(angle) degrees")
        }
        for angle in [231.0, 90.0, 309.0] {
            check(alpha(both, angle) < 0.1, "the ring is empty at \(angle) degrees")
        }
        let noDots = DotLayout(hidden: Set(StatusGlyph.allCases))
        let openBottom = bitmap(state(percent: 100, volume: 100), layout: noDots)
        check(alpha(openBottom, 270) < 0.15, "hiding every dot opens the bottom gap")

        // The two arcs are independent.
        let leftOnly = bitmap(state(percent: 100, volume: 0))
        let rightOnly = bitmap(state(percent: 0, volume: 100))
        check(alpha(leftOnly, 200) > 0.9 && alpha(leftOnly, 340) < 0.3, "battery alone only lights the left arc")
        check(alpha(rightOnly, 340) > 0.9 && alpha(rightOnly, 200) < 0.3, "volume alone only lights the right arc")

        // Low battery turns the left arc red and must stop being a template image.
        let lowBattery = state(percent: 15, volume: 60)
        let red = bitmap(lowBattery)
        let redColor = rgb(red, 200)
        check(alpha(red, 200) > 0.9 && redColor.r > 0.7 && redColor.g < 0.45,
              "15 percent on battery paints the left arc red")
        check(alpha(red, 340) > 0.9 && achromatic(pixel(red, angleDeg: 340)),
              "the volume arc keeps the menu bar colour while the battery is red")
        let twenty = bitmap(state(percent: 20, volume: 60))
        check(alpha(twenty, 200) > 0.9 && rgb(twenty, 200).r < 0.4, "20 percent is not the red state")
        let chargingLow = rgb(bitmap(state(percent: 15, volume: 60, charging: true)), 200)
        check(chargingLow.g > 0.5 && chargingLow.r < 0.45, "charging at 15 percent stays green")
        check(DuoIcon.image(status: lowBattery).isTemplate == false, "the red state is not a template image")
        check(DuoIcon.image(status: state(percent: 80, volume: 60)).isTemplate, "the normal state stays a template image")

        // The two new optional dots read public state only.
        var hot = state(percent: 80, volume: 60)
        hot.thermal = .serious
        check(StatusGlyph.thermal.isActive(in: hot), "a serious thermal state lights the thermal dot")
        hot.thermal = .fair
        check(!StatusGlyph.thermal.isActive(in: hot), "a fair thermal state stays quiet")
        var recording = state(percent: 80, volume: 60)
        recording.audio.micInUse = true
        check(StatusGlyph.microphone.isActive(in: recording), "a running input device lights the microphone dot")

        // Inactive dots keep their diameter and orbit; only the opacity changes.
        let inactive = state(percent: 80, volume: 60)
        let gray = bitmap(inactive)
        let dotAngle = 240.0 * Double.pi/180
        let dotX = DuoIcon.center.x + DuoIcon.radius*CGFloat(cos(dotAngle))
        let dotY = DuoIcon.center.y + DuoIcon.radius*CGFloat(sin(dotAngle))
        let px = Int(dotX*scale), py = gray.pixelsHigh - 1 - Int(dotY*scale)
        check(Double(gray.colorAt(x: px, y: py)!.alphaComponent) >= 0.49, "inactive dots stay visible at half opacity")
        let lit = bitmap(state(percent: 80, volume: 60, dots: [.vpn, .headphones, .mute, .focus]))
        let insideEdge = Int((dotX + DuoIcon.dotDiameter/2 - 0.2) * scale)
        let outsideEdge = Int((dotX + DuoIcon.dotDiameter/2 + 0.3) * scale)
        check(Double(lit.colorAt(x: insideEdge, y: py)!.alphaComponent) > 0.75, "dots keep their specified diameter")
        check(Double(lit.colorAt(x: outsideEdge, y: py)!.alphaComponent) < 0.1, "dot edges stop at the specified diameter")

        // The rotating ring carries the dots but never the Wi-Fi glyph.
        var orbitFrame = IconFrame.steady(state(percent: 100, volume: 100))
        orbitFrame.ringAngle = -.pi/2
        let orbited = bitmap(state(percent: 100, volume: 100), frame: orbitFrame)
        check(alpha(both, 250) < 0.15 && alpha(orbited, 250) > 0.9, "the arcs follow the rotation")
        var uprightWiFi = true
        for x in 96..<224 {
            for y in 84..<184 where both.colorAt(x: x, y: y) != orbited.colorAt(x: x, y: y) { uprightWiFi = false }
        }
        check(uprightWiFi, "Wi-Fi pixels remain upright while the outer circle turns")
        check(IconTurn.angle(at: 0) == 0, "the turn begins without a jump")
        check(IconTurn.angle(at: 1.07) < -2 * .pi, "the turn includes a small overshoot")
        check(abs(IconTurn.angle(at: IconTurn.duration) + 2 * .pi) < 0.00001, "the turn settles at one complete revolution")

        // Live layers: one layer per arc, one slot per glyph, two independent fills.
        let sample = state(percent: 75, volume: 40, dots: [.vpn, .headphones])
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 36, height: 28),
                              styleMask: .borderless, backing: .buffered, defer: false)
        let view = StatusIconView(frame: NSRect(x: 0, y: 0, width: 36, height: 28))
        window.contentView = view; window.orderFront(nil)
        defer { window.orderOut(nil) }
        view.update(sample); view.layoutSubtreeIfNeeded()
        let outer = view.layer!.sublayers![0]
        let center = view.layer!.sublayers![1]
        check(outer.animationKeys() == nil, "first sample stays still")
        let layers = outer.sublayers!
        check(layers.count == 5 + StatusGlyph.allCases.count, "five arc layers plus one layer per glyph")
        let trackLeft = layers[0] as! CAShapeLayer
        let battery = layers[1] as! CAShapeLayer
        let trackRight = layers[2] as! CAShapeLayer
        let volume = layers[3] as! CAShapeLayer
        let sweep = layers[4] as! CAShapeLayer
        let dotLayers = Array(layers.dropFirst(5))
        check(dotLayers.prefix(4).allSatisfy { !$0.isHidden } && dotLayers.dropFirst(4).allSatisfy { $0.isHidden },
              "only the four default dots are visible")
        check(abs(battery.lineWidth - 2.47) < 0.001 && abs(volume.lineWidth - 2.47) < 0.001,
              "both arcs use the 2.47 point stroke")
        check(abs(DuoIcon.radius*2 + DuoIcon.strokeWidth - 26) < 0.001, "the ring outer diameter stays 26 points")
        check(abs(battery.strokeEnd - 0.75) < 0.0001, "the battery arc follows the reported percentage")
        check(abs(volume.strokeEnd - 0.40) < 0.0001, "the volume arc follows the reported level")
        var mutedState = sample; mutedState.audio.muted = true
        view.update(mutedState)
        check(abs(volume.strokeEnd) < 0.0001, "muting empties the volume arc")
        view.update(sample)
        check(trackLeft.strokeEnd == 1 && trackRight.strokeEnd == 1, "tracks always draw the full arc")
        check(achromatic(pixel(both, angleDeg: 20)), "the volume arc is drawn in the label colour")
        for layer in layers.prefix(5) {
            let box = (layer as! CAShapeLayer).path!.boundingBox
            check(box.minX > -DuoIcon.strokeWidth && box.maxX < DuoIcon.size.width + DuoIcon.strokeWidth,
                  "arc paths stay inside the 32 point frame")
        }
        check(2 * (DuoIcon.radius + DuoIcon.dotDiameter/2) < outer.bounds.height,
              "the complete rotating dot envelope fits without clipping")
        for dot in dotLayers.prefix(4) {
            let shape = dot as! CAShapeLayer
            check(abs(shape.path!.boundingBox.width - 3.12) < 0.001, "live dots measure 3.12 points")
        }
        check(dotLayers[0].opacity == 1 && dotLayers[1].opacity == 1, "active dots light their own layers")
        check(dotLayers[2].opacity == 0.50 && dotLayers[3].opacity == 0.50, "inactive dots stay at half opacity")
        check(dotLayers[3].opacity == 0.50, "Focus off dims the correct dot")
        var focused = sample; focused.focus = .active
        view.update(focused)
        check(dotLayers[3].opacity == 1, "Focus on lights the real fourth layer")
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            check(outer.animation(forKey: "turn") is CAKeyframeAnimation, "a status event starts a composited turn")
            check(center.animation(forKey: "turn") == nil, "Wi-Fi stays upright")
            CATransaction.flush()
            let before = outer.animation(forKey: "turn")!.beginTime
            var batteryChange = focused; batteryChange.battery.percent = 99
            view.update(batteryChange); view.animateTurn()
            check(outer.animation(forKey: "turn")!.beginTime == before,
                  "battery updates and clicks do not restart an existing turn")
            view.stopAnimations(); view.animateTurn()
            check(outer.animation(forKey: "turn") != nil, "clicking the menu starts a fresh turn when idle")
        }

        // Colour precedence in the live layer: red, then low power yellow, then AC green.
        var lowBatteryState = sample; lowBatteryState.battery.percent = 15
        view.update(lowBatteryState)
        let liveRed = NSColor(cgColor: battery.strokeColor!)!.usingColorSpace(.deviceRGB)!
        check(liveRed.redComponent > 0.7 && liveRed.greenComponent < 0.45,
              "the live battery arc turns red below 20 percent")
        check(achromatic(NSColor(cgColor: volume.strokeColor!)!), "the live volume arc keeps the label colour")
        var powered = sample
        powered.battery.percent = 80; powered.battery.externalPower = true; powered.battery.charging = false
        view.update(powered)
        let ringGreen = NSColor(cgColor: battery.strokeColor!)!.usingColorSpace(.deviceRGB)!
        check(ringGreen.greenComponent > ringGreen.redComponent + 0.3,
              "AC power colors the live ring green before charging starts")
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            check(sweep.animation(forKey: "charging") != nil, "connecting power adds a short sweep")
        }
        powered.battery.lowPowerMode = true; view.update(powered)
        let lowPowerRing = NSColor(cgColor: battery.strokeColor!)!.usingColorSpace(.deviceRGB)!
        check(lowPowerRing.redComponent > 0.8 && lowPowerRing.greenComponent > 0.5 && lowPowerRing.blueComponent < 0.3,
              "low power yellow keeps overriding AC green, as before")
        powered.battery.lowPowerMode = false; view.update(powered)
        let restoredGreen = NSColor(cgColor: battery.strokeColor!)!.usingColorSpace(.deviceRGB)!
        check(restoredGreen.greenComponent > restoredGreen.redComponent + 0.3,
              "leaving low power mode restores AC green")
        powered.battery.charging = true; view.update(powered)
        powered.battery.externalPower = false; powered.battery.charging = false; view.update(powered)
        check(sweep.animation(forKey: "charging") == nil, "unplugging cancels the charging sweep")

        // Hiding dots narrows the layout back into a longer arc.
        let allVisible = DotLayout(hidden: [])
        view.update(sample, layout: allVisible)
        check(dotLayers.allSatisfy { !$0.isHidden }, "enabling every option shows eight dots")
        for (index, dot) in dotLayers.enumerated() {
            let box = (dot as! CAShapeLayer).path!.boundingBox
            var angle = atan2(box.midY - DuoIcon.center.y, box.midX - DuoIcon.center.x) * 180 / .pi
            if angle < 0 { angle += 360 }
            let expected = 270 + (CGFloat(index) - CGFloat(dotLayers.count - 1)/2) * DuoIcon.dotPitch
            check(abs(angle - expected) < 0.6, "dot \(index) sits on the expected orbit")
        }
        let wide = DuoIcon.RingGeometry(dotCount: 8)
        check(wide.bottomGap > geometry.bottomGap + 60, "eight dots widen the bottom gap")
        view.update(sample)
        check(dotLayers.dropFirst(4).allSatisfy { $0.isHidden }, "the default layout restores four dots")
        view.stopAnimations()
        check(outer.animationKeys() == nil && center.animationKeys() == nil, "stopping removes all live animations")
        print("PASS: split arcs, volume fill, warning colors, local dots, live layer states and orbit")
    }
}
