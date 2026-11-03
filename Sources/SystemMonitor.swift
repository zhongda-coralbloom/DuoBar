import AppKit
import Intents
import CoreAudio
import CoreWLAN
import IOKit.ps
import Network
import SystemConfiguration

final class SystemMonitor: NSObject, CWEventDelegate {
    var onChange: ((SystemStatus) -> Void)?
    private(set) var status = SystemStatus()
    private let worker = DispatchQueue(label: "com.corale.duobar.status", qos: .utility)
    private let wifi = CWWiFiClient.shared()
    private let path = NWPathMonitor()
    private var route: NetworkLink = .unknown
    private var timer: Timer?
    private var focusTimer: Timer?
    private var powerSource: CFRunLoopSource?
    private var dynamicStore: SCDynamicStore?
    private var observers: [NSObjectProtocol] = []
    private var audioListeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var focusObservation: NSKeyValueObservation?
    private var watchedOutput: AudioDeviceID?
    private var sampling = false
    private var needsAnotherSample = false
    private var sleeping = false
    private var menuOpen = false

    func start() {
        wifi.delegate = self
        for event: CWEventType in [.powerDidChange, .ssidDidChange, .linkDidChange, .linkQualityDidChange] {
            try? wifi.startMonitoringEvent(with: event)
        }
        path.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self else { return }
                if path.status != .satisfied { self.route = .offline }
                else if path.usesInterfaceType(.wifi) { self.route = .wifi }
                else if path.usesInterfaceType(.wiredEthernet) { self.route = .ethernet }
                else { self.route = .other }
                self.refresh()
            }
        }
        path.start(queue: worker)
        powerSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<SystemMonitor>.fromOpaque(context).takeUnretainedValue().refresh()
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let powerSource { CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        var context = SCDynamicStoreContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                            retain: nil, release: nil, copyDescription: nil)
        dynamicStore = SCDynamicStoreCreate(nil, "DuoBar" as CFString, { _, _, context in
            guard let context else { return }
            Unmanaged<SystemMonitor>.fromOpaque(context).takeUnretainedValue().refresh()
        }, &context)
        if let dynamicStore {
            let patterns = ["State:/Network/Global/.*", "State:/Network/Service/.*/.*", "State:/Network/Interface/.*/.*"] as CFArray
            SCDynamicStoreSetNotificationKeys(dynamicStore, nil, patterns)
            SCDynamicStoreSetDispatchQueue(dynamicStore, .main)
        }
        let system = AudioObjectID(kAudioObjectSystemObject)
        listen(system, SystemReaders.address(kAudioHardwarePropertyDevices))
        listen(system, SystemReaders.address(kAudioHardwarePropertyDefaultOutputDevice))
        bindOutput()
        observers.append(NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange,
            object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        observers.append(NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sleeping = true; self?.timer?.invalidate(); self?.focusTimer?.invalidate()
        })
        observers.append(nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sleeping = false; self?.resetTimer(); self?.refresh()
        })
        focusObservation = INFocusStatusCenter.default.observe(\.focusStatus, options: [.new]) { [weak self] _, _ in
            self?.refreshFocus()
        }
        resetTimer()
        refresh()
    }

    func setMenuOpen(_ open: Bool) {
        menuOpen = open
        resetTimer()
        if open { refresh() }
    }

    private func resetTimer() {
        timer?.invalidate()
        focusTimer?.invalidate()
        guard !sleeping else { return }
        let interval: TimeInterval = menuOpen ? 3 : 30
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = menuOpen ? 0.5 : 8
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // Supplement Focus notifications without re-reading audio and networking.
        let focusTimer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refreshFocus() }
        focusTimer.tolerance = 0.25
        RunLoop.main.add(focusTimer, forMode: .common)
        self.focusTimer = focusTimer
    }

    private func refreshFocus() {
        guard Thread.isMainThread else { DispatchQueue.main.async { self.refreshFocus() }; return }
        guard !sleeping else { return }
        worker.async { [weak self] in
            let focus = SystemReaders.focus()
            DispatchQueue.main.async {
                guard let self, !self.sleeping, self.status.focus != focus else { return }
                self.status.focus = focus
                self.onChange?(self.status)
            }
        }
    }

    func refresh() {
        guard Thread.isMainThread else { DispatchQueue.main.async { self.refresh() }; return }
        guard !sleeping else { return }
        if sampling { needsAnotherSample = true; return }
        sampling = true
        let route = self.route
        worker.async { [weak self] in
            guard let self else { return }
            var value = SystemStatus()
            value.battery = SystemReaders.battery()
            value.wifi = SystemReaders.wifi(client: self.wifi, route: route)
            value.vpn = SystemReaders.vpn()
            value.audio = SystemReaders.audio()
            value.focus = SystemReaders.focus()
            value.thermal = ProcessInfo.processInfo.thermalState
            DispatchQueue.main.async {
                self.sampling = false
                self.bindOutput()
                self.bindInputs()
                if value != self.status {
                    self.status = value
                    self.onChange?(value)
                }
                if self.needsAnotherSample { self.needsAnotherSample = false; self.refresh() }
            }
        }
    }

    private func listen(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) {
        var address = address
        guard AudioObjectHasProperty(object, &address) else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.refresh() }
        if AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr {
            audioListeners.append((object, address, block))
        }
    }

    private func bindOutput() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let device: AudioDeviceID? = SystemReaders.value(system, kAudioHardwarePropertyDefaultOutputDevice)
        guard device != watchedOutput else { return }
        if let old = watchedOutput {
            for (object, original, block) in audioListeners where object == old {
                var address = original
                AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
            }
            audioListeners.removeAll { $0.0 == old }
        }
        watchedOutput = device
        guard let device, device != kAudioObjectUnknown else { return }
        for selector in [kAudioDevicePropertyMute, kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyDataSource] {
            for element: UInt32 in [0, 1, 2] {
                listen(device, SystemReaders.address(selector, scope: kAudioDevicePropertyScopeOutput, element: element))
            }
        }
    }

    /// Microphone use is a per-device property, so input devices are watched separately.
    /// Idempotent: it only reconciles the running-somewhere listeners, never the output ones.
    private func bindInputs() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let devices: [AudioDeviceID] = SystemReaders.values(system, kAudioHardwarePropertyDevices)
        var inputs: Set<AudioDeviceID> = []
        for device in devices {
            let streams: [AudioStreamID] = SystemReaders.values(device, kAudioDevicePropertyStreams,
                                                               scope: kAudioDevicePropertyScopeInput)
            if !streams.isEmpty { inputs.insert(device) }
        }
        let mic = kAudioDevicePropertyDeviceIsRunningSomewhere
        let watched = Set(audioListeners.filter { $0.1.mSelector == mic }.map { $0.0 })
        guard inputs != watched else { return }
        for (object, original, block) in audioListeners where original.mSelector == mic && !inputs.contains(object) {
            var address = original
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
        }
        audioListeners.removeAll { $0.1.mSelector == mic && !inputs.contains($0.0) }
        for device in inputs where !watched.contains(device) {
            listen(device, SystemReaders.address(mic))
        }
    }

    func powerStateDidChangeForWiFiInterface(withName name: String) { refresh() }
    func ssidDidChangeForWiFiInterface(withName name: String) { refresh() }
    func linkDidChangeForWiFiInterface(withName name: String) { refresh() }
    func linkQualityDidChangeForWiFiInterface(withName name: String, rssi: Int, transmitRate: Double) { refresh() }

    func stop() {
        timer?.invalidate()
        focusTimer?.invalidate()
        path.cancel()
        try? wifi.stopMonitoringAllEvents()
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        if let dynamicStore { SCDynamicStoreSetDispatchQueue(dynamicStore, nil) }
        for (object, original, block) in audioListeners {
            var address = original
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
        }
        focusObservation?.invalidate()
        observers.forEach {
            NotificationCenter.default.removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
            DistributedNotificationCenter.default().removeObserver($0)
        }
    }
}
