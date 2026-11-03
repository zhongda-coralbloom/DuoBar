import AppKit
import ServiceManagement
import CoreLocation
import Intents

final class SettingsController: NSWindowController, CLLocationManagerDelegate {
    private let preferences: DotPreferences
    private let dotRows = NSStackView()
    private let login = NSButton(checkboxWithTitle: "登录时自动启动", target: nil, action: nil)
    private let focusStatus = NSTextField(wrappingLabelWithString: "")
    private let location = CLLocationManager()
    private let icon = LargeIconView()
    var onRefresh: (() -> Void)?

    init(preferences: DotPreferences) {
        self.preferences = preferences
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 496, height: 780),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "DuoBar 设置"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        location.delegate = self
        build()
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        guard let content = window?.contentView else { return }
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 11
        stack.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 26),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -26),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 22)
        ])
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 60).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 48).isActive = true
        let name = NSTextField(labelWithString: "DuoBar")
        name.font = .systemFont(ofSize: 21, weight: .semibold)
        let caption = NSTextField(labelWithString: "一个位置，读懂 Mac 的状态。")
        caption.font = .systemFont(ofSize: 12); caption.textColor = .secondaryLabelColor
        let names = NSStackView(views: [name, caption]); names.orientation = .vertical; names.alignment = .leading; names.spacing = 5
        let header = NSStackView(views: [icon, names]); header.spacing = 15
        stack.addArrangedSubview(header)
        addSeparator(stack)
        login.target = self; login.action = #selector(toggleLogin)
        stack.addArrangedSubview(login)
        stack.addArrangedSubview(note("只在菜单栏显示。单击查看，点击外部或 Esc 收起。"))
        stack.addArrangedSubview(note("位置：按住 ⌘ 拖到控制中心左侧。macOS 会记住你调整的位置。"))
        addSeparator(stack)
        stack.addArrangedSubview(heading("底部圆点"))
        stack.addArrangedSubview(note("从左到右排列。圆点大小一致，开启时点亮，未开启时置灰。取消勾选可隐藏这一项。"))
        dotRows.orientation = .vertical; dotRows.alignment = .leading; dotRows.spacing = 4
        stack.addArrangedSubview(dotRows)
        dotRows.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        rebuildDotRows()
        addSeparator(stack)
        stack.addArrangedSubview(heading("整理系统菜单栏"))
        stack.addArrangedSubview(note("在系统设置中关闭原生 Wi-Fi、电池的菜单栏显示，即可留出空间。"))
        stack.addArrangedSubview(button("关闭对应状态栏", #selector(openMenuBar)))
        addSeparator(stack)
        stack.addArrangedSubview(heading("状态读取"))
        focusStatus.font = .systemFont(ofSize: 12)
        focusStatus.textColor = .secondaryLabelColor
        stack.addArrangedSubview(focusStatus)
        let actions = NSStackView(views: [
            button("允许读取专注状态…", #selector(explainFocus)),
            button("允许显示 Wi-Fi 名称…", #selector(requestLocation))
        ])
        actions.spacing = 8
        stack.addArrangedSubview(actions)
        stack.addArrangedSubview(note("Wi-Fi 名称需定位权限，应用不请求地理坐标。专注状态未共享时，圆点保持灰色，详情标注未共享。"))
        addSeparator(stack)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        stack.addArrangedSubview(note("\(version) · 本地运行"))
    }

    private func rebuildDotRows() {
        for row in dotRows.arrangedSubviews { dotRows.removeArrangedSubview(row); row.removeFromSuperview() }
        for (index, glyph) in preferences.layout.order.enumerated() {
            let check = NSButton(checkboxWithTitle: glyph.title, target: self, action: #selector(toggleDot(_:)))
            check.identifier = NSUserInterfaceItemIdentifier(glyph.rawValue)
            check.state = preferences.layout.hidden.contains(glyph) ? .off : .on
            check.setAccessibilityLabel("显示" + glyph.title + "圆点")
            let image = NSImageView(image: NSImage(systemSymbolName: glyph.symbol, accessibilityDescription: nil) ?? NSImage())
            image.contentTintColor = .secondaryLabelColor
            image.widthAnchor.constraint(equalToConstant: 22).isActive = true
            let spacer = NSView()
            let up = NSButton(image: NSImage(systemSymbolName: "chevron.up", accessibilityDescription: nil)!, target: self, action: #selector(moveDotUp(_:)))
            let down = NSButton(image: NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)!, target: self, action: #selector(moveDotDown(_:)))
            for b in [up, down] {
                b.bezelStyle = .rounded; b.controlSize = .small
                b.identifier = NSUserInterfaceItemIdentifier(glyph.rawValue)
                b.widthAnchor.constraint(equalToConstant: 30).isActive = true
            }
            up.isEnabled = index > 0; down.isEnabled = index < preferences.layout.order.count - 1
            up.setAccessibilityLabel(glyph.title + "向前移"); down.setAccessibilityLabel(glyph.title + "向后移")
            up.toolTip = "向左移动"; down.toolTip = "向右移动"
            let row = NSStackView(views: [image, check, spacer, up, down])
            row.spacing = 8; row.alignment = .centerY
            row.heightAnchor.constraint(equalToConstant: 28).isActive = true
            dotRows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: dotRows.widthAnchor).isActive = true
        }
        icon.layout = preferences.layout
    }
    @objc private func toggleDot(_ sender: NSButton) {
        guard let value = sender.identifier?.rawValue, let glyph = StatusGlyph(rawValue: value) else { return }
        preferences.setVisible(sender.state == .on, for: glyph)
        icon.layout = preferences.layout
    }
    @objc private func moveDotUp(_ sender: NSButton) { moveDot(sender, by: -1) }
    @objc private func moveDotDown(_ sender: NSButton) { moveDot(sender, by: 1) }
    private func moveDot(_ sender: NSButton, by offset: Int) {
        guard let value = sender.identifier?.rawValue, let glyph = StatusGlyph(rawValue: value) else { return }
        preferences.move(glyph, by: offset)
        rebuildDotRows()
    }

    private func addSeparator(_ stack: NSStackView) {
        let line = NSBox(); line.boxType = .separator
        stack.addArrangedSubview(line)
        line.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    private func note(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11); label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = 444
        return label
    }
    private func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold); return label
    }
    private func button(_ text: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: text, target: self, action: action)
        button.bezelStyle = .rounded; button.controlSize = .small; return button
    }

    func update(_ status: SystemStatus) {
        icon.status = status
        icon.layout = preferences.layout
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        switch status.focus {
        case .unavailable: focusStatus.stringValue = "点击下方按钮并在系统弹窗中允许读取。还需在系统设置中开启“共享专注状态”。"
        default: focusStatus.stringValue = "专注状态可读 · " + status.focus.title
        }
    }
    func present(status: SystemStatus) {
        update(status)
        showWindow(nil); NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleLogin() {
        do {
            if login.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "自动启动尚未完成"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
    @objc private func openMenuBar() { SystemSettings.open(.menubar) }
    @objc private func requestLocation() { location.requestWhenInUseAuthorization() }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { onRefresh?() }

    @objc private func explainFocus() {
        let center = INFocusStatusCenter.default
        if center.authorizationStatus == .denied || center.authorizationStatus == .restricted {
            let alert = NSAlert()
            alert.messageText = "专注状态尚未共享"
            alert.informativeText = "请在系统设置中允许 DuoBar 读取专注状态，并在专注模式 → 专注状态中开启共享。DuoBar 只读取是否专注，开启时点亮圆点。"
            alert.addButton(withTitle: "打开专注设置")
            alert.addButton(withTitle: "稍后")
            if alert.runModal() == .alertFirstButtonReturn { SystemSettings.open(.focus) }
            return
        }
        center.requestAuthorization { [weak self] _ in
            DispatchQueue.main.async { self?.onRefresh?() }
        }
    }
}
