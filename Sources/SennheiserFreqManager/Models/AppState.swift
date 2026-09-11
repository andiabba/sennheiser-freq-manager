import Foundation
import Combine

class AppState: ObservableObject {
    @Published var devices: [SennheiserDevice] = []
    @Published var showFile: WWBShowFile?
    @Published var assignments: [String: String] = [:]
    @Published var statusMessage: String = ""
    @Published var isScanning: Bool = false

    let deviceDiscovery = DeviceDiscovery()
    let sennheiserProtocol = SennheiserProtocol()
    private var binaryConnections: [String: BinaryProtocol] = [:]
    private var cancellables = Set<AnyCancellable>()

    init() {
        deviceDiscovery.$discoveredDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newDevices in
                guard let self = self else { return }
                let existingIDs = Set(self.devices.map { $0.id })
                for device in newDevices where !existingIDs.contains(device.id) {
                    self.queryDeviceState(device)
                }
                self.mergeDiscoveredDevices(newDevices)
            }
            .store(in: &cancellables)
    }

    private func mergeDiscoveredDevices(_ discovered: [SennheiserDevice]) {
        var updated = devices
        let discoveredIDs = Set(discovered.map { $0.id })
        updated.removeAll { !discoveredIDs.contains($0.id) && $0.isOnline }
        for disc in discovered {
            if updated.firstIndex(where: { $0.id == disc.id }) == nil {
                updated.append(disc)
            }
        }
        devices = updated
    }

    func startDiscovery() {
        isScanning = true
        statusMessage = "Scanning for devices…"
        deviceDiscovery.startBrowsing()

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.isScanning = false
            if self?.devices.isEmpty == true {
                self?.statusMessage = "No devices found. Check network connection."
            } else {
                let count = self?.devices.count ?? 0
                self?.statusMessage = "\(count) device(s) found"
            }
        }
    }

    func stopDiscovery() {
        deviceDiscovery.stopBrowsing()
        isScanning = false
    }

    func addManualDevice(name: String, host: String) {
        let device = SennheiserDevice(id: UUID().uuidString, name: name, host: host)
        devices.append(device)
        queryDeviceState(device)
    }

    func loadShowFile(url: URL) {
        do {
            let showFile = try WWBParser.parse(fileURL: url)
            self.showFile = showFile
            statusMessage = "Loaded \(showFile.fileName): \(showFile.entries.count) frequencies"
        } catch {
            statusMessage = "Error loading file: \(error.localizedDescription)"
        }
    }

    func assignFrequency(entryID: String, deviceID: String) {
        assignments[entryID] = deviceID
    }

    func sendFrequency(entry: WWBFrequencyEntry, to device: SennheiserDevice) {
        sennheiserProtocol.setFrequency(device: device, frequencyKHz: entry.frequencyKHz) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.statusMessage = "Set \(device.name) to \(entry.frequencyDisplayString)"
                    self?.updateDevice(device.id) { $0.frequencyKHz = entry.frequencyKHz }
                case .failure(let error):
                    self?.statusMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    func sendAllAssignments() {
        guard let showFile = showFile else { return }
        for (entryID, deviceID) in assignments {
            guard let entry = showFile.entries.first(where: { $0.id == entryID }),
                  let device = devices.first(where: { $0.id == deviceID }) else { continue }
            sendFrequency(entry: entry, to: device)
        }
    }

    // MARK: - Query all device state

    func queryDeviceState(_ device: SennheiserDevice) {
        let p = sennheiserProtocol
        let id = device.id

        p.queryName(device: device) { [weak self] r in
            if case .success(let v) = r { self?.mainUpdate(id) { $0.name = v } }
        }
        // Frequency returns freq + bank + channel in one response
        p.queryFrequencyInfo(device: device) { [weak self] r in
            if case .success(let info) = r {
                self?.mainUpdate(id) {
                    $0.frequencyKHz = info.frequencyKHz
                    $0.bank = info.bank
                    $0.channel = info.channel
                }
            }
        }
        p.querySensitivity(device: device) { [weak self] r in
            if case .success(let v) = r { self?.mainUpdate(id) { $0.sensitivity = v } }
        }
        p.queryMode(device: device) { [weak self] r in
            if case .success(let v) = r { self?.mainUpdate(id) { $0.mode = v } }
        }
        p.queryMute(device: device) { [weak self] r in
            if case .success(let v) = r { self?.mainUpdate(id) { $0.rfMute = v } }
        }
        p.queryEqualizer(device: device) { _ in }

        // Establish binary connection early to receive state updates
        _ = getBinaryConnection(for: device)
    }

    // MARK: - Set individual parameters
    // All setters update local state immediately, then send command in background.

    func setDeviceName(_ device: SennheiserDevice, name: String) {
        updateDevice(device.id) { $0.name = name }
        sennheiserProtocol.setName(device: device, name: name) { [weak self] r in
            if case .failure = r { DispatchQueue.main.async { self?.statusMessage = "Failed to set name" } }
        }
    }

    func setDeviceFrequency(_ device: SennheiserDevice, frequencyKHz: Int) {
        updateDevice(device.id) { $0.frequencyKHz = frequencyKHz }
        let mhz = Double(frequencyKHz) / 1000.0
        statusMessage = "Frequency set to \(String(format: "%.3f MHz", mhz))"
        sennheiserProtocol.setFrequency(device: device, frequencyKHz: frequencyKHz) { [weak self] r in
            if case .failure(let e) = r { DispatchQueue.main.async { self?.statusMessage = "Error: \(e.localizedDescription)" } }
        }
    }

    func setDeviceBank(_ device: SennheiserDevice, bank: Int) {
        updateDevice(device.id) { $0.bank = bank }
        sennheiserProtocol.setBank(device: device, bank: bank) { [weak self] r in
            if case .failure = r { DispatchQueue.main.async { self?.statusMessage = "Failed to set bank" } }
        }
    }

    func setDeviceChannel(_ device: SennheiserDevice, channel: Int) {
        updateDevice(device.id) { $0.channel = channel }
        sennheiserProtocol.setChannel(device: device, channel: channel) { [weak self] r in
            if case .failure = r { DispatchQueue.main.async { self?.statusMessage = "Failed to set channel" } }
        }
    }

    func setDeviceSensitivity(_ device: SennheiserDevice, dB: Int) {
        updateDevice(device.id) { $0.sensitivity = dB }
        sennheiserProtocol.setSensitivity(device: device, dB: dB) { _ in }
    }

    func setDeviceMode(_ device: SennheiserDevice, mode: SennheiserDevice.TxMode) {
        updateDevice(device.id) { $0.mode = mode }
        sennheiserProtocol.setMode(device: device, mode: mode) { _ in }
    }

    func setDeviceMute(_ device: SennheiserDevice, muted: Bool) {
        updateDevice(device.id) { $0.rfMute = muted }
        sennheiserProtocol.setMute(device: device, muted: muted) { _ in }
    }

    // MARK: - Binary protocol parameters (port 8133)

    private func getBinaryConnection(for device: SennheiserDevice) -> BinaryProtocol {
        if let existing = binaryConnections[device.id] {
            return existing
        }
        let conn = BinaryProtocol()
        let deviceId = device.id
        conn.onStateUpdate = { [weak self] state in
            self?.mainUpdate(deviceId) {
                if !state.name.isEmpty { $0.name = state.name }
                $0.frequencyKHz = state.frequencyKHz
                $0.bank = state.bank
                $0.channel = state.channel
                $0.mode = state.txMode == 0 ? .stereo : .mono
                $0.autoLock = state.txAutoLock
                $0.rfPower = state.rfPower
                $0.warningAfPeak = state.warnAfPeak
                $0.warningRfMute = state.warnRfMute
                // RX params: 0x00 = ignored (sync off), non-zero = synced value
                let rawRxAutoLock = state.raw[39]
                let rawBalance = state.raw[40]
                let rawMode = state.raw[41]
                let rawLimiter = state.raw[42]
                let rawHighBoost = state.raw[43]
                let rawSquelch = state.raw[44]
                $0.rxAutoLock = rawRxAutoLock >= 0x02
                $0.rxAutoLockSync = rawRxAutoLock != 0
                $0.rxBalanceSync = rawBalance != 0
                if rawBalance != 0 { $0.rxBalance = state.rxBalance }
                $0.rxModeSync = rawMode != 0
                if rawMode != 0 { $0.rxMode = rawMode == 1 ? .stereo : .focus }
                $0.rxLimiterSync = rawLimiter != 0
                if rawLimiter != 0 { $0.rxLimiter = state.rxLimiter }
                $0.rxHighBoostSync = rawHighBoost != 0
                if rawHighBoost != 0 { $0.rxHighBoost = state.rxHighBoost }
                $0.rxSquelchSync = rawSquelch != 0
                if rawSquelch != 0 { $0.rxSquelch = state.rxSquelch }
            }
        }
        conn.connect(deviceIP: device.host)
        binaryConnections[device.id] = conn
        return conn
    }

    func setDeviceAutoLock(_ device: SennheiserDevice, locked: Bool) {
        updateDevice(device.id) { $0.autoLock = locked }
        getBinaryConnection(for: device).setTxAutoLock(locked)
    }

    func setDeviceRfPower(_ device: SennheiserDevice, mW: Int) {
        updateDevice(device.id) { $0.rfPower = mW }
        getBinaryConnection(for: device).setRfPower(mW: mW)
    }

    func setDeviceWarningAfPeak(_ device: SennheiserDevice, enabled: Bool) {
        updateDevice(device.id) { $0.warningAfPeak = enabled }
        getBinaryConnection(for: device).setWarnAfPeak(enabled)
    }

    func setDeviceWarningRfMute(_ device: SennheiserDevice, enabled: Bool) {
        updateDevice(device.id) { $0.warningRfMute = enabled }
        getBinaryConnection(for: device).setWarnRfMute(enabled)
    }

    func setRxAutoLock(_ device: SennheiserDevice, locked: Bool) {
        updateDevice(device.id) { $0.rxAutoLock = locked }
        getBinaryConnection(for: device).setRxAutoLock(locked: locked)
    }

    func setRxBalance(_ device: SennheiserDevice, value: Int) {
        updateDevice(device.id) { $0.rxBalance = value }
        getBinaryConnection(for: device).setRxBalance(value)
    }

    func setRxMode(_ device: SennheiserDevice, mode: SennheiserDevice.RxMode) {
        updateDevice(device.id) { $0.rxMode = mode }
        getBinaryConnection(for: device).setRxMode(stereo: mode == .stereo)
    }

    func setRxLimiter(_ device: SennheiserDevice, value: Int) {
        updateDevice(device.id) { $0.rxLimiter = value }
        getBinaryConnection(for: device).setRxLimiter(dB: value)
    }

    func setRxHighBoost(_ device: SennheiserDevice, enabled: Bool) {
        updateDevice(device.id) { $0.rxHighBoost = enabled }
        getBinaryConnection(for: device).setRxHighBoost(enabled)
    }

    func setRxSquelch(_ device: SennheiserDevice, value: Int) {
        updateDevice(device.id) { $0.rxSquelch = value }
        getBinaryConnection(for: device).setRxSquelch(dB: value)
    }

    // MARK: - RX Sync Enable/Ignore flags
    // Value 0x00 = ignored (don't sync), non-zero = sync with this value

    func setRxAutoLockSync(_ device: SennheiserDevice, enabled: Bool) {
        updateDevice(device.id) { $0.rxAutoLockSync = enabled }
        let conn = getBinaryConnection(for: device)
        if enabled {
            conn.setRxAutoLock(locked: device.rxAutoLock)
        } else {
            conn.ignoreParameter(.rxAutoLock)
        }
    }

    func setRxBalanceSync(_ device: SennheiserDevice, enabled: Bool) {
        updateDevice(device.id) { $0.rxBalanceSync = enabled }
        let conn = getBinaryConnection(for: device)
        if enabled {
            conn.setRxBalance(device.rxBalance)
        } else {
            conn.ignoreParameter(.rxBalance)
        }
    }

    func setRxModeSync(_ device: SennheiserDevice, enabled: Bool) {
        updateDevice(device.id) { $0.rxModeSync = enabled }
        let conn = getBinaryConnection(for: device)
        if enabled {
            conn.setRxMode(stereo: device.rxMode == .stereo)
        } else {
            conn.ignoreParameter(.rxMode)
        }
    }

    func setRxLimiterSync(_ device: SennheiserDevice, enabled: Bool) {
        updateDevice(device.id) { $0.rxLimiterSync = enabled }
        let conn = getBinaryConnection(for: device)
        if enabled {
            conn.setRxLimiter(dB: device.rxLimiter)
        } else {
            conn.ignoreParameter(.rxLimiter)
        }
    }

    func setRxHighBoostSync(_ device: SennheiserDevice, enabled: Bool) {
        updateDevice(device.id) { $0.rxHighBoostSync = enabled }
        let conn = getBinaryConnection(for: device)
        if enabled {
            conn.setRxHighBoost(device.rxHighBoost)
        } else {
            conn.ignoreParameter(.rxHighBoost)
        }
    }

    func setRxSquelchSync(_ device: SennheiserDevice, enabled: Bool) {
        updateDevice(device.id) { $0.rxSquelchSync = enabled }
        let conn = getBinaryConnection(for: device)
        if enabled {
            conn.setRxSquelch(dB: device.rxSquelch)
        } else {
            conn.ignoreParameter(.rxSquelch)
        }
    }

    // MARK: - Helpers

    private func updateDevice(_ id: String, _ update: (inout SennheiserDevice) -> Void) {
        if let idx = devices.firstIndex(where: { $0.id == id }) {
            update(&devices[idx])
        }
    }

    private func mainUpdate(_ id: String, _ update: @escaping (inout SennheiserDevice) -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.updateDevice(id, update)
        }
    }
}
