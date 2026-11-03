import AppKit

@main struct PanelTests {
    static func check(_ value: Bool, _ message: String) {
        guard value else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    static func descendants(_ view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(descendants)
    }
    static func rows(_ panel: StatusPanel) -> [StatusRow] {
        descendants(panel).compactMap { $0 as? StatusRow }
    }
    static func row(_ panel: StatusPanel, _ id: String) -> StatusRow? {
        rows(panel).first { $0.accessibilityIdentifier() == "status-" + id }
    }

    static func main() {
        _ = NSApplication.shared
        let panel = StatusPanel()
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 314, height: 482),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = panel; window.orderFront(nil)
        defer { window.orderOut(nil) }
        var layout = DotLayout()
        layout.hidden.insert(.headphones)
        var state = SystemStatus.preview()
        state.audio.muted = false
        state.audio.volume = 42
        state.audio.micInUse = true
        panel.update(state, layout: layout)
        panel.layoutSubtreeIfNeeded()

        // Two pinned rows plus one row per status item: the panel mirrors the settings list.
        check(rows(panel).count == 10, "two pinned rows and eight status rows are controls")
        check(row(panel, "wifi") != nil && row(panel, "battery") != nil, "Wi-Fi and battery stay pinned")
        for glyph in StatusGlyph.allCases {
            check(row(panel, glyph.rawValue) != nil, "the panel lists \(glyph.title)")
        }
        check(row(panel, "headphones")?.isListed == false, "an unchecked item is still listed but dimmed")
        check(row(panel, "vpn")?.isListed == true, "a checked item stays bright")
        check(row(panel, "microphone")?.accessibilityLabel()?.contains("使用中") == true,
              "the microphone row reports live use")
        check(row(panel, "lowPowerMode")?.accessibilityLabel()?.contains("已关闭") == true,
              "the low power row reports its state")

        // Volume row: a real slider that reports whole percentages.
        let volumes = descendants(panel).compactMap { $0 as? VolumeRow }
        check(volumes.count == 1, "exactly one volume row")
        let sliders = descendants(panel).compactMap { $0 as? NSSlider }
        check(sliders.count == 1, "exactly one slider")
        check(sliders[0].minValue == 0 && sliders[0].maxValue == 100, "the slider covers 0 to 100 percent")
        var level: Int?
        panel.onVolume = { level = $0 }
        sliders[0].doubleValue = 37
        sliders[0].sendAction(sliders[0].action, to: sliders[0].target)
        check(level == 37, "dragging writes the new level")
        check(volumes[0].accessibilityLabel() == "音量 37%", "the row shows the level it wrote")

        // Navigation: every actionable row opens its page, read-only rows never do.
        var opened: [SystemSettings.Page] = []
        panel.onOpenSettings = { opened.append($0) }
        row(panel, "battery")?.performClick(nil)
        row(panel, "headphones")?.performClick(nil)
        row(panel, "mute")?.performClick(nil)
        row(panel, "focus")?.performClick(nil)
        row(panel, "lowPowerMode")?.performClick(nil)
        row(panel, "microphone")?.performClick(nil)
        row(panel, "powerAdapter")?.performClick(nil)
        check(opened == [.battery, .bluetooth, .sound, .focus, .battery, .microphone, .battery],
              "actionable rows open their settings pages")
        row(panel, "vpn")?.performClick(nil)
        row(panel, "thermal")?.performClick(nil)
        check(opened.count == 7, "read-only rows never navigate")

        // Wi-Fi row offers a menu instead of jumping straight to settings.
        let beforeMenu = opened.count
        row(panel, "wifi")?.performClick(nil)
        check(opened.count == beforeMenu, "the Wi-Fi row opens its menu instead of the settings pane")
        var wired = SystemStatus(); wired.wifi.route = .ethernet
        panel.update(wired, layout: layout)
        check(row(panel, "wifi")?.accessibilityLabel()?.contains("以太网") == true,
              "an Ethernet link is labelled as such")
        var wireless = wired; wireless.wifi.associated = true; wireless.wifi.ssid = "Home"
        panel.update(wireless, layout: layout)
        check(row(panel, "wifi")?.accessibilityLabel()?.contains("Wi-Fi") == true,
              "an associated Wi-Fi link is labelled Wi-Fi")

        // Menu ordering: connected first, then strongest signal.
        let networks = [WiFiNetwork(ssid: "weak", rssi: -85, secured: true),
                        WiFiNetwork(ssid: "strong", rssi: -40, secured: false),
                        WiFiNetwork(ssid: "home", rssi: -70, secured: true)]
        check(WiFiMenuOrder.sorted(networks, connected: "home").map(\.ssid) == ["home", "strong", "weak"],
              "the connected network leads, then the strongest signal")
        check(WiFiMenuOrder.sorted(networks, connected: nil).map(\.ssid) == ["strong", "home", "weak"],
              "without a connected network the strongest wins")
        check(WiFiMenuOrder.signalBars(-50) == 3 && WiFiMenuOrder.signalBars(-70) == 2
              && WiFiMenuOrder.signalBars(-80) == 1, "signal bars follow the RSSI thresholds")

        check(SystemSettings.Page.allCases.allSatisfy { $0.url.scheme == "x-apple.systempreferences" },
              "settings links stay within the system settings application")
        check(SystemSettings.Page.bluetooth.url.absoluteString
              == "x-apple.systempreferences:com.apple.BluetoothSettings", "headphones target Bluetooth settings")
        check(SystemSettings.Page.microphone.url.absoluteString.contains("Privacy_Microphone"),
              "microphone points at the privacy pane")
        check(panel.frame.height >= 470, "the panel grew to fit eight status rows")
        print("PASS: pinned rows, full status list, volume slider, Wi-Fi menu order and settings links")
    }
}
