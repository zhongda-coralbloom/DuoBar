import AppKit

enum SystemSettings {
    enum Page: String, CaseIterable {
        case wifi, network, battery, vpn, bluetooth, sound, focus, microphone, menubar

        var title: String {
            switch self {
            case .wifi: return "Wi-Fi 设置"
            case .network: return "网络设置"
            case .battery: return "电池设置"
            case .vpn: return "VPN 设置"
            case .bluetooth: return "蓝牙设置"
            case .sound: return "声音设置"
            case .focus: return "专注模式设置"
            case .microphone: return "麦克风隐私设置"
            case .menubar: return "菜单栏设置"
            }
        }

        var url: URL {
            let target: String
            switch self {
            case .wifi: target = "com.apple.wifi-settings-extension"
            case .network: target = "com.apple.Network-Settings.extension"
            case .battery: target = "com.apple.Battery-Settings.extension"
            case .vpn: target = "com.apple.NetworkExtensionSettingsUI.NESettingsUIExtension"
            case .bluetooth: target = "com.apple.BluetoothSettings"
            case .sound: target = "com.apple.Sound-Settings.extension"
            case .focus: target = "com.apple.Focus-Settings.extension"
            case .microphone: target = "com.apple.preference.security?Privacy_Microphone"
            case .menubar: target = "com.apple.ControlCenter-Settings.extension"
            }
            return URL(string: "x-apple.systempreferences:" + target)!
        }
    }

    @discardableResult static func open(_ page: Page) -> Bool {
        NSWorkspace.shared.open(page.url)
    }
}
