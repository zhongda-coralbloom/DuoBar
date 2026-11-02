import Foundation

enum FocusState: Equatable {
    case off
    case active
    case unavailable(String)
    var isActive: Bool { self == .active }
    var title: String {
        switch self {
        case .off: return "未开启"
        case .active: return "已开启"
        case .unavailable: return "状态未共享"
        }
    }
    var symbol: String { isActive ? "moon.fill" : "moon" }
    static func shared(_ value: Bool?) -> FocusState {
        guard let value else { return .unavailable("系统尚未共享专注状态") }
        return value ? .active : .off
    }
}

struct BatteryState: Equatable {
    var present = false
    var percent: Int?
    var charging = false
    var externalPower = false
    var minutesRemaining: Int?
    var lowPowerMode = false
    // AC can be connected before the battery starts charging, or while charging is paused.
    var connectedToPower: Bool { present && (externalPower || charging) }
    var title: String { percent.map { "\($0)%" } ?? (present ? "读取中" : "外接电源") }
    var detail: String {
        if !present { return "此 Mac 没有内置电池" }
        if charging { return "正在充电" }
        if externalPower { return percent == 100 ? "电量已充满" : "已连接电源 · 未充电" }
        if let minutesRemaining, minutesRemaining > 0 {
            return "电池供电 · 约 \(minutesRemaining / 60) 小时 \(minutesRemaining % 60) 分钟"
        }
        return "电池供电"
    }
}

enum NetworkLink: String { case wifi, ethernet, other, offline, unknown }
struct WiFiState: Equatable {
    var available = false
    var powered = false
    var associated = false
    var ssid: String?
    var rssi: Int?
    var route: NetworkLink = .unknown
    var title: String {
        if associated { return ssid ?? "已连接 Wi-Fi" }
        if route == .ethernet { return "以太网已连接" }
        if !available { return "无 Wi-Fi 接口" }
        return powered ? "Wi-Fi 未连接" : "Wi-Fi 已关闭"
    }
    var detail: String {
        if associated {
            let quality = signalQuality
            return (ssid == nil ? "网络名称受系统保护 · " : "") + quality
        }
        if route == .ethernet { return "正在使用有线网络" }
        return route == .offline ? "没有可用网络路径" : "点开 Wi-Fi 设置管理连接"
    }
    var signalLevel: Int {
        guard associated else { return 0 }
        return rssi.map { $0 >= -60 ? 3 : ($0 >= -72 ? 2 : 1) } ?? 3
    }
    var signalQuality: String {
        guard associated else { return powered ? "未连接" : "已关闭" }
        guard let rssi else { return "已连接" }
        if rssi >= -60 { return "信号很好" }
        if rssi >= -72 { return "信号一般" }
        return "信号较弱"
    }
    var symbol: String {
        if associated { return "wifi" }
        if route == .ethernet { return "network" }
        return powered ? "wifi.exclamationmark" : "wifi.slash"
    }
}

struct VPNState: Equatable {
    var names: [String] = []
    var available = true
    var hasUnidentifiedTunnel = false
    var routedTunnel = false
    var systemProxy = false
    var active: Bool { !names.isEmpty || routedTunnel || systemProxy }
    var title: String {
        if !names.isEmpty { return names.joined(separator: "、") }
        if routedTunnel { return "已连接" }
        if systemProxy { return "系统代理已开启" }
        if !available { return "状态不可用" }
        if hasUnidentifiedTunnel { return "检测到未识别隧道" }
        return "未连接"
    }
}

struct AudioState: Equatable {
    var outputName = "声音输出不可用"
    var headphoneNames: [String] = []
    var muted: Bool?
    var volume: Int?
    /// Any input device is being used by some process (CoreAudio HAL, no microphone permission needed).
    var micInUse = false
    var headphoneActive: Bool { !headphoneNames.isEmpty }
    var headphoneTitle: String { headphoneActive ? headphoneNames.joined(separator: "、") : "未连接" }
    var soundTitle: String {
        if muted == true { return "已静音" }
        if let volume { return "\(volume)%" }
        return muted == false ? "未静音" : "设备不提供音量状态"
    }
    var volumeSummary: String {
        if muted == true { return "已静音" }
        if let volume { return "音量 \(volume)%" }
        return "音量不可用"
    }
}

enum StatusGlyph: String, CaseIterable {
    case vpn, headphones, mute, focus, lowPowerMode, microphone, thermal, powerAdapter
    var title: String {
        switch self {
        case .vpn: return "VPN"
        case .headphones: return "耳机"
        case .mute: return "静音"
        case .focus: return "专注"
        case .lowPowerMode: return "低电量模式"
        case .microphone: return "麦克风"
        case .thermal: return "过热"
        case .powerAdapter: return "外接电源"
        }
    }
    var symbol: String {
        switch self {
        case .vpn: return "key.horizontal"
        case .headphones: return "headphones"
        case .mute: return "speaker.slash.fill"
        case .focus: return "moon.fill"
        case .lowPowerMode: return "bolt.fill"
        case .microphone: return "mic.fill"
        case .thermal: return "thermometer.high"
        case .powerAdapter: return "powerplug"
        }
    }
    func isActive(in status: SystemStatus) -> Bool {
        switch self {
        case .vpn: return status.vpn.active
        case .headphones: return status.audio.headphoneActive
        case .mute: return status.audio.muted == true
        case .focus: return status.focus.isActive
        case .lowPowerMode: return status.battery.lowPowerMode
        case .microphone: return status.audio.micInUse
        case .thermal: return status.thermal == .serious || status.thermal == .critical
        case .powerAdapter: return status.battery.connectedToPower
        }
    }
    var label: String {
        switch self {
        case .vpn: return "VPN 已连接"
        case .headphones: return "耳机已连接"
        case .mute: return "已静音"
        case .focus: return "专注已开启"
        case .lowPowerMode: return "低电量模式已开启"
        case .microphone: return "麦克风使用中"
        case .thermal: return "散热受限，性能降低"
        case .powerAdapter: return "已接电源"
        }
    }
}

struct SystemStatus: Equatable {
    var battery = BatteryState()
    var wifi = WiFiState()
    var vpn = VPNState()
    var audio = AudioState()
    var focus: FocusState = .unavailable("需要读取系统专注状态")
    var thermal: ProcessInfo.ThermalState = .nominal
    var glyphs: [StatusGlyph] { StatusGlyph.allCases.filter { $0.isActive(in: self) } }
    var accessibilitySummary: String {
        (["DuoBar", "电量 \(battery.title)", audio.volumeSummary, wifi.title] + glyphs.map(\.label))
            .joined(separator: "，")
    }
    static func preview() -> SystemStatus {
        var s = SystemStatus()
        s.battery = BatteryState(present: true, percent: 87, charging: false, externalPower: false, minutesRemaining: nil)
        s.wifi = WiFiState(available: true, powered: true, associated: true, ssid: "Home Wi-Fi", rssi: -48, route: .wifi)
        s.vpn.names = ["个人 VPN"]
        s.audio = AudioState(outputName: "AirPods Pro", headphoneNames: ["AirPods Pro"], muted: true, volume: 0)
        s.focus = .active
        return s
    }
}


extension SystemStatus {
    func shouldAnimate(from previous: SystemStatus) -> Bool {
        let old = previous.wifi
        return glyphs != previous.glyphs ||
            wifi.available != old.available || wifi.powered != old.powered ||
            wifi.associated != old.associated || wifi.ssid != old.ssid ||
            wifi.signalLevel != old.signalLevel ||
            (!wifi.associated && wifi.route != old.route)
    }
}
