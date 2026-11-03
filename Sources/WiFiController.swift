import AppKit
import CoreWLAN
import CoreLocation
import Security

/// One nearby network as the menu needs it. Names can be missing without Location access.
struct WiFiNetwork: Equatable {
    let ssid: String
    let rssi: Int
    let secured: Bool
}

/// Ordering rule for the hover menu: strongest signal first, the connected network pinned on top.
enum WiFiMenuOrder {
    static func sorted(_ networks: [WiFiNetwork], connected: String?) -> [WiFiNetwork] {
        networks.sorted { left, right in
            if left.ssid == connected { return true }
            if right.ssid == connected { return false }
            if left.rssi != right.rssi { return left.rssi > right.rssi }
            return left.ssid < right.ssid
        }
    }
    static func signalBars(_ rssi: Int) -> Int {
        if rssi >= -60 { return 3 }
        if rssi >= -72 { return 2 }
        return 1
    }
}

/// Scanning, connecting and remembering passwords. Scanning blocks for a second or two,
/// so callers run `scan()` off the main thread.
final class WiFiController: NSObject, CLLocationManagerDelegate {
    enum Failure: LocalizedError {
        case noInterface
        case staleScan
        case scanFailed(String)
        case associateFailed(String)

        var errorDescription: String? {
            switch self {
            case .noInterface: return "这台 Mac 没有可用的 Wi-Fi 接口。"
            case .staleScan: return "扫描结果已过期，请重新扫描后再连接。"
            case .scanFailed(let reason): return "扫描失败：\(reason)"
            case .associateFailed(let reason): return "连接失败：\(reason)"
            }
        }
    }

    private static let keychainService = "com.corale.duobar.wifi"

    private let location = CLLocationManager()
    private let client = CWWiFiClient.shared()
    private var scanned: [String: CWNetwork] = [:]
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var onAuthorizationChange: (() -> Void)?

    override init() {
        super.init()
        location.delegate = self
        authorizationStatus = location.authorizationStatus
    }

    var hasLocationAccess: Bool { authorizationStatus == .authorized }
    /// Names are only readable with Location access; the scan itself works without it.
    func requestAuthorization() {
        guard location.authorizationStatus == .notDetermined else { return }
        location.requestWhenInUseAuthorization()
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        DispatchQueue.main.async { self.onAuthorizationChange?() }
    }

    var connectedSSID: String? { client.interface()?.ssid() }

    /// Blocking. Returns networks strongest-first with the connected one on top.
    func scan() -> Result<[WiFiNetwork], Failure> {
        guard let interface = client.interface() else { return .failure(.noInterface) }
        guard interface.powerOn() else { return .success([]) }
        do {
            let found = try interface.scanForNetworks(withSSID: nil, includeHidden: false)
            var cache: [String: CWNetwork] = [:]
            var list: [WiFiNetwork] = []
            for network in found {
                // A nil SSID means Location access is missing, not that the name is secret.
                guard let ssid = network.ssid, !ssid.isEmpty else { continue }
                cache[ssid] = network
                list.append(WiFiNetwork(ssid: ssid, rssi: network.rssiValue,
                                       secured: !network.supportsSecurity(.none)))
            }
            scanned = cache
            return .success(WiFiMenuOrder.sorted(list, connected: interface.ssid()))
        } catch {
            return .failure(.scanFailed(error.localizedDescription))
        }
    }

    func connect(to network: WiFiNetwork, password: String?) -> Result<Void, Failure> {
        guard let interface = client.interface() else { return .failure(.noInterface) }
        guard let target = scanned[network.ssid] else { return .failure(.staleScan) }
        do {
            try interface.associate(to: target, password: password)
            if let password, !password.isEmpty { storePassword(password, for: network.ssid) }
            return .success(())
        } catch {
            return .failure(.associateFailed(error.localizedDescription))
        }
    }

    // MARK: - Keychain

    private func query(for ssid: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.keychainService,
         kSecAttrAccount as String: ssid]
    }

    func storedPassword(for ssid: String) -> String? {
        var request = query(for: ssid)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func storePassword(_ password: String, for ssid: String) {
        let data = Data(password.utf8)
        let base = query(for: ssid)
        if SecItemCopyMatching(base as CFDictionary, nil) == errSecSuccess {
            SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        } else {
            var addition = base
            addition[kSecValueData as String] = data
            SecItemAdd(addition as CFDictionary, nil)
        }
    }
}

/// The hover menu under the Wi-Fi row. Scanning happens after the menu is on screen so a
/// slow scan never blocks the panel from opening.
final class WiFiMenu: NSObject, NSMenuDelegate {
    private let controller: WiFiController
    private let menu = NSMenu()
    private var networks: [WiFiNetwork] = []
    private var connected: String?
    private var scanning = false
    private var connectInFlight = false
    var onRefresh: (() -> Void)?

    init(controller: WiFiController) {
        self.controller = controller
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
    }

    func present(from view: NSView, connected ssid: String?) {
        connected = ssid
        scanning = false
        showPlaceholder()
        controller.requestAuthorization()
        menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.minX + 6, y: view.bounds.minY + 4), in: view)
        startScan()
    }

    func menuWillOpen(_ menu: NSMenu) { startScan() }

    private func startScan() {
        guard !scanning else { return }
        scanning = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.controller.scan()
            DispatchQueue.main.async {
                self.scanning = false
                switch result {
                case .success(let list):
                    self.networks = list
                    self.connected = self.controller.connectedSSID ?? self.connected
                    self.rebuild()
                case .failure(let failure):
                    self.rebuild(message: failure.localizedDescription)
                }
            }
        }
    }

    private func showPlaceholder() {
        menu.removeAllItems()
        let item = NSMenuItem(title: "正在扫描附近的网络…", action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
        appendFooter()
    }

    private func rebuild(message: String? = nil) {
        menu.removeAllItems()
        if let message {
            let item = NSMenuItem(title: message, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else if networks.isEmpty {
            let item = NSMenuItem(title: controller.hasLocationAccess ? "没有找到可用的网络" : "允许定位后才会显示网络名称",
                                  action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for network in networks {
                let item = NSMenuItem(title: network.ssid, action: #selector(pick(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = network
                item.image = NSImage(systemSymbolName: network.secured ? "lock.fill" : "wifi",
                                     accessibilityDescription: nil)
                item.state = network.ssid == connected ? .on : .off
                menu.addItem(item)
            }
        }
        if !controller.hasLocationAccess {
            let grant = NSMenuItem(title: "允许读取网络名称…", action: #selector(requestAccess), keyEquivalent: "")
            grant.target = self
            menu.addItem(grant)
        }
        appendFooter()
    }

    private func appendFooter() {
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "打开 Wi-Fi 设置…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
    }

    @objc private func requestAccess() {
        controller.requestAuthorization()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openSettings() { SystemSettings.open(.wifi) }

    @objc private func pick(_ sender: NSMenuItem) {
        guard let network = sender.representedObject as? WiFiNetwork, !connectInFlight else { return }
        guard network.secured else { connect(network, password: nil); return }
        if let saved = controller.storedPassword(for: network.ssid) {
            connect(network, password: saved)
            return
        }
        guard let password = promptPassword(for: network) else { return }
        connect(network, password: password)
    }

    private func promptPassword(for network: WiFiNetwork) -> String? {
        let alert = NSAlert()
        alert.messageText = "连接「\(network.ssid)」"
        alert.informativeText = "这个网络需要密码。密码会保存在本机钥匙串，下次直接连接。"
        alert.addButton(withTitle: "连接")
        alert.addButton(withTitle: "取消")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "Wi-Fi 密码"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return nil }
        return field.stringValue
    }

    private func connect(_ network: WiFiNetwork, password: String?) {
        connectInFlight = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.controller.connect(to: network, password: password)
            DispatchQueue.main.async {
                self.connectInFlight = false
                if case .failure(let failure) = result {
                    let alert = NSAlert()
                    alert.messageText = "无法连接到「\(network.ssid)」"
                    alert.informativeText = failure.localizedDescription
                    alert.addButton(withTitle: "好")
                    alert.runModal()
                }
                self.onRefresh?()
            }
        }
    }

}
