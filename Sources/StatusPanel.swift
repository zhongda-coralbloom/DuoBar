import AppKit

final class StatusRow: NSButton {
    var destination: SystemSettings.Page
    var onActivate: (() -> Void)?
    /// Fired when the pointer enters or leaves the row, so the panel can offer a submenu.
    var onHoverChange: ((Bool) -> Void)?
    private var hover = false
    private var hoverTracking: NSTrackingArea?
    private let chevron = NSImageView()
    private let symbol = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let detailField = NSTextField(labelWithString: "")
    private let valueField = NSTextField(labelWithString: "")
    override var allowsVibrancy: Bool { true }

    init(height: CGFloat, destination: SystemSettings.Page, compact: Bool = false, identifier: String? = nil) {
        self.destination = destination
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: height))
        title = ""
        isBordered = false
        setButtonType(.momentaryChange)
        focusRingType = .default
        target = self; action = #selector(activateRow)
        setAccessibilityIdentifier("status-" + (identifier ?? destination.rawValue))
        chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .medium))
        chevron.contentTintColor = .tertiaryLabelColor
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: height).isActive = true
        symbol.imageScaling = .scaleProportionallyDown
        titleField.font = .systemFont(ofSize: 13, weight: compact ? .regular : .semibold)
        detailField.font = .systemFont(ofSize: 11)
        detailField.textColor = .secondaryLabelColor
        detailField.lineBreakMode = .byTruncatingTail
        valueField.font = .systemFont(ofSize: 12, weight: .medium)
        valueField.textColor = .secondaryLabelColor
        valueField.alignment = .right
        valueField.lineBreakMode = .byTruncatingMiddle
        valueField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        [symbol, titleField, detailField, valueField, chevron].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false; addSubview($0)
        }
        NSLayoutConstraint.activate([
            symbol.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            symbol.widthAnchor.constraint(equalToConstant: compact ? 19 : 24),
            symbol.heightAnchor.constraint(equalToConstant: compact ? 19 : 24),
            symbol.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor, constant: compact ? 0 : -8),
            titleField.widthAnchor.constraint(lessThanOrEqualToConstant: compact ? 78 : 145),
            detailField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            detailField.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -10),
            detailField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 3),
            valueField.leadingAnchor.constraint(greaterThanOrEqualTo: titleField.trailingAnchor, constant: 10),
            valueField.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -10),
            valueField.centerYAnchor.constraint(equalTo: titleField.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 8),
            chevron.heightAnchor.constraint(equalToConstant: 12),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        detailField.isHidden = compact
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking); hoverTracking = tracking
    }
    override func mouseEntered(with event: NSEvent) {
        hover = isEnabled; needsDisplay = true
        onHoverChange?(true)
    }
    override func mouseExited(with event: NSEvent) {
        hover = false; needsDisplay = true
        onHoverChange?(false)
    }
    override func draw(_ dirtyRect: NSRect) {
        if hover || isHighlighted {
            NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.12 : 0.06).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: 6, yRadius: 6).fill()
        }
        super.draw(dirtyRect)
    }
    func setNavigationEnabled(_ enabled: Bool) {
        isEnabled = enabled
        chevron.isHidden = !enabled
        if !enabled { hover = false }
        needsDisplay = true
    }
    /// Whether this row is also drawn as a ring dot.
    private(set) var isListed = true
    /// An item the user unchecked still appears in the panel, just quieter than a listed one.
    func setListed(_ value: Bool) {
        guard isListed != value || titleField.textColor == .labelColor else { return }
        isListed = value
        titleField.textColor = value ? .labelColor : .tertiaryLabelColor
        valueField.textColor = value ? .secondaryLabelColor : .tertiaryLabelColor
        symbol.alphaValue = value ? 1 : 0.55
    }
    @objc private func activateRow() { if isEnabled { onActivate?() } }

    func update(symbol name: String, title: String, detail: String = "", value: String = "", active: Bool = true) {
        symbol.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 18, weight: .medium))
        symbol.contentTintColor = active ? .labelColor : .tertiaryLabelColor
        titleField.stringValue = title
        detailField.stringValue = detail
        valueField.stringValue = value
        toolTip = [title, value, detail].filter { !$0.isEmpty }.joined(separator: " · ")
        setAccessibilityElement(true)
        setAccessibilityRole(isEnabled ? .button : .staticText)
        setAccessibilityLabel(toolTip)
        setAccessibilityHelp(isEnabled ? "打开" + destination.title : nil)
        [symbol, titleField, detailField, valueField, chevron].forEach { $0.setAccessibilityElement(false) }
        titleField.textColor = isListed ? .labelColor : .tertiaryLabelColor
        symbol.alphaValue = isListed ? 1 : 0.55
    }
}

/// A row that writes the output level instead of navigating anywhere.
final class VolumeRow: NSView {
    var onLevel: ((Int) -> Void)?
    private let symbol = NSImageView()
    private let titleField = NSTextField(labelWithString: "音量")
    private let valueField = NSTextField(labelWithString: "")
    private let slider = NSSlider(value: 50, minValue: 0, maxValue: 100, target: nil, action: nil)
    private(set) var level: Int?

    init(height: CGFloat = 44) {
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: height))
        symbol.imageScaling = .scaleProportionallyDown
        titleField.font = .systemFont(ofSize: 13, weight: .regular)
        valueField.font = .systemFont(ofSize: 12, weight: .medium)
        valueField.alignment = .right
        valueField.textColor = .secondaryLabelColor
        slider.target = self
        slider.action = #selector(levelChanged)
        slider.isContinuous = true
        slider.controlSize = .small
        heightAnchor.constraint(equalToConstant: height).isActive = true
        [symbol, titleField, slider, valueField].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false; addSubview($0)
        }
        NSLayoutConstraint.activate([
            symbol.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            symbol.widthAnchor.constraint(equalToConstant: 19),
            symbol.heightAnchor.constraint(equalToConstant: 19),
            symbol.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleField.widthAnchor.constraint(equalToConstant: 34),
            slider.leadingAnchor.constraint(equalTo: titleField.trailingAnchor, constant: 8),
            slider.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueField.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: 8),
            valueField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            valueField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func levelChanged() {
        let value = Int(slider.doubleValue.rounded())
        level = value
        valueField.stringValue = "\(value)%"
        setAccessibilityLabel("音量 \(value)%")
        onLevel?(value)
    }

    func update(muted: Bool?, volume: Int?) {
        // Skip while the pointer is down so dragging is never fought by a refresh.
        if NSEvent.pressedMouseButtons == 0 {
            if let volume { slider.doubleValue = Double(volume) }
            level = volume
        }
        let silent = muted == true
        slider.isEnabled = !silent
        symbol.image = NSImage(systemSymbolName: silent ? "speaker.slash.fill" : "speaker.wave.2",
                               accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 17, weight: .medium))
        symbol.contentTintColor = silent ? .tertiaryLabelColor : .labelColor
        valueField.stringValue = silent ? "已静音" : (volume.map { "\($0)%" } ?? "—")
        setAccessibilityElement(true)
        setAccessibilityLabel("音量 " + valueField.stringValue)
        [symbol, titleField, slider, valueField].forEach { $0.setAccessibilityElement(false) }
    }
}

final class StatusPanel: NSView {
    static let panelSize = NSSize(width: 314, height: 462)
    var onOpenSettings: ((SystemSettings.Page) -> Void)?
    var onRefresh: (() -> Void)?
    var onVolume: ((Int) -> Void)?
    var wifiMenu: WiFiMenu?
    private let wifi = StatusRow(height: 55, destination: .wifi)
    private let battery = StatusRow(height: 55, destination: .battery)
    private let volume = VolumeRow()
    private let statusStack = NSStackView()
    private var statusRows: [StatusGlyph: StatusRow] = [:]
    private var listed: [StatusGlyph] = []
    private var connectedSSID: String?
    private var hoverWork: DispatchWorkItem?
    private let title = NSTextField(labelWithString: "DuoBar")
    private let mode = NSTextField(labelWithString: "此 Mac")
    override var allowsVibrancy: Bool { true }

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.panelSize))
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        mode.font = .systemFont(ofSize: 11)
        mode.textColor = .secondaryLabelColor
        let spacer = NSView()
        let header = NSStackView(views: [title, spacer, mode])
        header.orientation = .horizontal; header.alignment = .centerY
        header.heightAnchor.constraint(equalToConstant: 30).isActive = true
        let separator = NSBox()
        separator.boxType = .separator
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        let gap = NSView(); gap.heightAnchor.constraint(equalToConstant: 4).isActive = true
        statusStack.orientation = .vertical
        statusStack.alignment = .leading
        statusStack.spacing = 0
        let stack = NSStackView(views: [header, wifi, battery, volume, separator, gap, statusStack])
        stack.orientation = .vertical
        stack.alignment = .leading; stack.spacing = 0
        for row in stack.arrangedSubviews { row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 5)
        ])
        // Wi-Fi opens the hover menu; the battery row keeps its jump to system settings.
        wifi.onActivate = { [weak self] in self?.presentWiFiMenu() }
        wifi.onHoverChange = { [weak self] inside in self?.scheduleWiFiMenu(inside: inside) }
        battery.onActivate = { [weak self] in self?.onOpenSettings?(.battery) }
        volume.onLevel = { [weak self] percent in self?.onVolume?(percent) }
        buildStatusRows()
        update(SystemStatus(), layout: DotLayout())
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildStatusRows() {
        for glyph in StatusGlyph.allCases {
            let row = StatusRow(height: 33, destination: destination(for: glyph), compact: true, identifier: glyph.rawValue)
            row.onActivate = { [weak self] in
                guard let page = self?.destination(for: glyph) else { return }
                self?.onOpenSettings?(page)
            }
            if !navigates(glyph) { row.setNavigationEnabled(false) }
            statusRows[glyph] = row
        }
    }

    private func destination(for glyph: StatusGlyph) -> SystemSettings.Page {
        switch glyph {
        case .vpn: return .vpn
        case .headphones: return .bluetooth
        case .mute: return .sound
        case .focus: return .focus
        case .lowPowerMode, .powerAdapter, .thermal: return .battery
        case .microphone: return .microphone
        }
    }
    /// VPN and thermal pressure are read-only in system settings, so no chevron there.
    private func navigates(_ glyph: StatusGlyph) -> Bool {
        switch glyph {
        case .vpn, .thermal: return false
        default: return true
        }
    }

    /// The status list mirrors the settings list exactly; unchecked items stay visible but quiet.
    private func applyOrder(_ layout: DotLayout) {
        guard layout.order != listed else { return }
        for row in statusStack.arrangedSubviews {
            statusStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        for glyph in layout.order {
            guard let row = statusRows[glyph] else { continue }
            statusStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: statusStack.widthAnchor).isActive = true
            row.setListed(layout.visible.contains(glyph))
        }
        listed = layout.order
    }

    func update(_ state: SystemStatus, layout: DotLayout, preview: Bool = false) {
        mode.stringValue = preview ? "样例状态" : "此 Mac"
        connectedSSID = state.wifi.associated ? state.wifi.ssid : nil
        wifi.destination = state.wifi.route == .ethernet && !state.wifi.associated ? .network : .wifi
        wifi.update(symbol: state.wifi.symbol,
                    title: state.wifi.route == .ethernet && !state.wifi.associated ? "以太网" : "Wi-Fi",
                    detail: state.wifi.title,
                    value: state.wifi.associated ? state.wifi.signalQuality : "",
                    active: state.wifi.associated || state.wifi.route == .ethernet)
        wifi.toolTip = state.wifi.detail + " · 悬停展开附近网络"
        let batterySymbol = state.battery.charging ? "battery.100percent.bolt" : "battery.75percent"
        battery.update(symbol: state.battery.present ? batterySymbol : "powerplug",
                       title: "电池", detail: state.battery.detail, value: state.battery.title)
        volume.update(muted: state.audio.muted, volume: state.audio.volume)
        applyOrder(layout)
        for glyph in layout.order {
            guard let row = statusRows[glyph] else { continue }
            row.update(symbol: glyph.symbol, title: glyph.title,
                       value: value(for: glyph, in: state), active: glyph.isActive(in: state))
            row.setListed(layout.visible.contains(glyph))
            if glyph == .focus, case .unavailable(let reason) = state.focus { row.toolTip = reason }
            if glyph == .vpn, state.vpn.hasUnidentifiedTunnel {
                row.toolTip = "检测到网络隧道，但 macOS 未提供可确认的 VPN 名称；不会据此点亮点。"
            }
        }
    }

    private func value(for glyph: StatusGlyph, in state: SystemStatus) -> String {
        switch glyph {
        case .vpn: return state.vpn.title
        case .headphones: return state.audio.headphoneTitle
        case .mute: return state.audio.muted == true ? "已静音" : "未静音"
        case .focus: return state.focus.title
        case .lowPowerMode: return state.battery.lowPowerMode ? "已开启" : "已关闭"
        case .microphone: return state.audio.micInUse ? "使用中" : "未使用"
        case .thermal: return state.thermal == .nominal ? "正常" : (state.thermal == .fair ? "偏高" : "受限")
        case .powerAdapter: return state.battery.connectedToPower ? "已接电源" : "未接电源"
        }
    }

    private func scheduleWiFiMenu(inside: Bool) {
        hoverWork?.cancel()
        guard inside, wifi.isEnabled, wifiMenu != nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.presentWiFiMenu() }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
    }

    private func presentWiFiMenu() {
        hoverWork?.cancel()
        wifiMenu?.present(from: wifi, connected: connectedSSID)
    }
}

final class LargeIconView: NSView {
    var status = SystemStatus.preview() { didSet { needsDisplay = true } }
    var layout = DotLayout() { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        DuoIcon.draw(status: status, layout: layout, in: bounds, color: .labelColor)
    }
}
