import AppKit
import Intents
import CoreAudio
import CoreWLAN
import IOKit.ps
import Network
import SystemConfiguration

enum SystemReaders {
    static func battery() -> BatteryState {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return BatteryState()
        }
        for source in sources {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = d[kIOPSCurrentCapacityKey] as? Int
            let maximum = d[kIOPSMaxCapacityKey] as? Int
            let percent: Int? = {
                guard let current, let maximum, maximum > 0 else { return nil }
                return max(0, min(100, Int((Double(current) / Double(maximum) * 100).rounded())))
            }()
            return BatteryState(present: true, percent: percent,
                charging: d[kIOPSIsChargingKey] as? Bool ?? false,
                externalPower: d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                minutesRemaining: d[kIOPSTimeToEmptyKey] as? Int,
                lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
        }
        return BatteryState()
    }

    static func wifi(client: CWWiFiClient, route: NetworkLink) -> WiFiState {
        guard let interface = client.interface() else { return WiFiState(route: route) }
        let power = interface.powerOn()
        let rssi = interface.rssiValue()
        // SSID may be nil without Location permission, even on a connected interface.
        let associated = power && (interface.interfaceMode() == .station || interface.ssid() != nil || (rssi < 0 && rssi > -128))
        return WiFiState(available: true, powered: power, associated: associated,
                         ssid: associated ? interface.ssid() : nil,
                         rssi: associated && rssi < 0 && rssi > -128 ? rssi : nil, route: route)
    }

    static func vpn() -> VPNState {
        guard let prefs = SCPreferencesCreate(nil, "DuoBar" as CFString, nil),
              let services = SCNetworkServiceCopyAll(prefs) as? [SCNetworkService] else {
            return VPNState(available: false)
        }
        var state = VPNState()
        for service in services {
            guard SCNetworkServiceGetEnabled(service),
                  let interface = SCNetworkServiceGetInterface(service),
                  let type = SCNetworkInterfaceGetInterfaceType(interface) as String?,
                  ["VPN", "IPSec", "PPP"].contains(type),
                  let serviceID = SCNetworkServiceGetServiceID(service),
                  let connection = SCNetworkConnectionCreateWithServiceID(nil, serviceID, nil, nil)
            else { continue }
            if SCNetworkConnectionGetStatus(connection) == .connected {
                state.names.append((SCNetworkServiceGetName(service) as String?) ?? "VPN")
            }
        }
        // A utun alone is NOT proof of a VPN. Apple uses tunnels for other services.
        if !state.active, let store = SCDynamicStoreCreate(nil, "DuoBar" as CFString, nil, nil),
           let keys = SCDynamicStoreCopyKeyList(store, "State:/Network/Service/.*/IPv4" as CFString) as? [String] {
            for key in keys {
                guard let d = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
                      let name = d["InterfaceName"] as? String, name.hasPrefix("utun") else { continue }
                state.hasUnidentifiedTunnel = true
            }
        }
        state.routedTunnel = !TunnelRoutePolicy.activeInterfaces(TunnelRoutes.read()).isEmpty
        if let proxies = SCDynamicStoreCopyProxies(nil) as? [String: Any] {
            let keys = ["HTTPEnable", "HTTPSEnable", "SOCKSEnable", "ProxyAutoConfigEnable"]
            func enabled(_ d: [String: Any]) -> Bool {
                keys.contains { (d[$0] as? NSNumber)?.boolValue == true }
            }
            state.systemProxy = enabled(proxies)
            if let scoped = proxies["__SCOPED__"] as? [String: [String: Any]] {
                state.systemProxy = state.systemProxy || scoped.values.contains(where: enabled)
            }
        }
        state.names.sort()
        return state
    }

    static func focus() -> FocusState {
        let center = INFocusStatusCenter.default
        guard center.authorizationStatus == .authorized else {
            return .unavailable("在 DuoBar 设置中允许读取专注状态。仅读取是否专注，不区分具体模式。")
        }
        return .shared(center.focusStatus.isFocused)
    }

    static func audio() -> AudioState {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let devices: [AudioDeviceID] = values(system, kAudioHardwarePropertyDevices)
        let defaultOutput: AudioDeviceID? = value(system, kAudioHardwarePropertyDefaultOutputDevice)
        var result = AudioState()
        for device in devices {
            let alive: UInt32 = value(device, kAudioDevicePropertyDeviceIsAlive) ?? 0
            guard alive != 0 else { continue }
            // An input device that is running somewhere means some process is recording.
            let inputStreams: [AudioStreamID] = values(device, kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeInput)
            if !inputStreams.isEmpty {
                let running: UInt32 = value(device, kAudioDevicePropertyDeviceIsRunningSomewhere) ?? 0
                if running != 0 { result.micInUse = true }
            }
            let streams: [AudioStreamID] = values(device, kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
            guard !streams.isEmpty else { continue }
            let name = string(device, kAudioObjectPropertyName) ?? "耳机"
            let headphoneTerminal = streams.contains { stream in
                let terminal: UInt32? = value(stream, kAudioStreamPropertyTerminalType)
                return terminal == kAudioStreamTerminalTypeHeadphones
            }
            let transport: UInt32? = value(device, kAudioDevicePropertyTransportType)
            let wireless = transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
            let headphoneName = ["airpods", "beats", "buds", "headphone", "headset", "earphone", "耳机", "wh-1000", "wf-1000"].contains { name.lowercased().contains($0) }
            if headphoneTerminal || (wireless && headphoneName) { result.headphoneNames.append(name) }
        }
        result.headphoneNames = Array(Set(result.headphoneNames)).sorted()
        guard let device = defaultOutput, device != kAudioObjectUnknown else { return result }
        result.outputName = string(device, kAudioObjectPropertyName) ?? "当前输出设备"
        let mute: UInt32? = value(device, kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        result.muted = mute.map { $0 != 0 }
        let master: Float32? = value(device, kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput)
        let volume: Float32? = master ?? {
            let left: Float32? = value(device, kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: 1)
            let right: Float32? = value(device, kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: 2)
            let channels = [left, right].compactMap { $0 }
            return channels.isEmpty ? nil : channels.reduce(0, +) / Float(channels.count)
        }()
        result.volume = volume.map { max(0, min(100, Int(($0 * 100).rounded()))) }
        // Volume zero is a silent output even when a device exposes no mute switch.
        if volume == 0 { result.muted = true }
        return result
    }

    static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func value<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                         element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> T? {
        var a = address(selector, scope: scope, element: element)
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<T>.alignment)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &a, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.load(as: T.self)
    }

    static func values<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                          scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [T] {
        var a = address(selector, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<T>.alignment)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &a, 0, nil, &size, pointer) == noErr else { return [] }
        return Array(UnsafeBufferPointer(start: pointer.assumingMemoryBound(to: T.self), count: Int(size) / MemoryLayout<T>.size))
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var a = address(selector)
        var ref: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &a, 0, nil, &size, &ref) == noErr else { return nil }
        return ref?.takeRetainedValue() as String?
    }
}
