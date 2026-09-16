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
    private let binaryProtocol = BinaryProtocol.shared
    private var registeredDeviceIPs: Set<String> = []
    private var cancellables = Set<AnyCancellable>()

    init() {
        deviceDiscovery.$discoveredDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newDevices in
                guard let self = self else { return }
                let existingIDs = Set(self.devices.map { $0.id })
                for device in newDevices where !existingIDs.contains(device.id) {
                    self.querySSCState(device)
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
        binaryProtocol.shutdown()
        registeredDeviceIPs.removeAll()

        isScanning = true
        statusMessage = "Scanning for devices…"
        deviceDiscovery.startBrowsing()

        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self = self else { return }
            self.isScanning = false
            if self.devices.isEmpty {
                self.statusMessage = "No devices found. Check network connection."
            } else {
                self.statusMessage = "\(self.devices.count) device(s) found"
                for device in self.devices {
                    self.registerBinaryDevice(device)
                }
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

    // MARK: - Query device state

    private func querySSCState(_ device: SennheiserDevice) {
        let p = sennheiserProtocol
        let id = device.id

        p.queryName(device: device) { [weak self] r in
            if case .success(let v) = r { self?.mainUpdate(id) { $0.name = v } }
        }
        p.queryFrequencyInfo(device: device) { [weak self] r in
            if case .success(let info) = r {
                self?.mainUpdate(id) {
                    $0.frequencyKHz = info.frequencyKHz
                    $0.bank = info.bank
                    $0.channel = info.channel > 0 ? info.channel : nil
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
    }

    func queryDeviceState(_ device: SennheiserDevice) {
        querySSCState(device)
        registerBinaryDevice(device)
    }

    // MARK: - Binary protocol (shared socket on port 8133)

    private func registerBinaryDevice(_ device: SennheiserDevice) {
        let ip = device.host
        guard !registeredDeviceIPs.contains(ip) else { return }
        registeredDeviceIPs.insert(ip)

        let deviceId = device.id
        binaryProtocol.addDevice(ip: ip) { [weak self] state in
            self?.mainUpdate(deviceId) {
                if !state.name.isEmpty { $0.name = state.name }
                $0.frequencyKHz = state.frequencyKHz
                $0.bank = state.bank
                $0.channel = state.channel > 0 ? state.channel : nil
                $0.sensitivity = state.sensitivity
                $0.mode = state.txMode == 0 ? .stereo : .mono
                $0.autoLock = state.txAutoLock
                $0.rfPower = state.rfPower
                $0.warningAfPeak = state.warnAfPeak
                $0.warningRfMute = state.warnRfMute
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
    }

    // MARK: - Set individual parameters

    func setDeviceName(_ device: SennheiserDevice, name: String) {
        updateDevice(device.id) { $0.name = name }
        sennheiserProtocol.setName(device: device, name: name) { [weak self] r in
            if case .failure = r { DispatchQueue.main.async { self?.statusMessage = "Failed to set name" } }
        }
    }

    func setDeviceBankChannel(_ device: SennheiserDevice, bank: Int, channel: Int, frequencyKHz: Int) {
        updateDevice(device.id) { $0.bank = bank; $0.channel = channel; $0.frequencyKHz = frequencyKHz }
        let mhz = Double(frequencyKHz) / 1000.0
        statusMessage = "Bank \(bank) Ch \(channel) → \(String(format: "%.3f MHz", mhz))"
        sennheiserProtocol.setFrequency(device: device, frequencyKHz: frequencyKHz) { [weak self] r in
            if case .failure(let e) = r { DispatchQueue.main.async { self?.statusMessage = "Error: \(e.localizedDescription)" } }
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
        let table = FrequencyTable.detectRange(frequencyKHz: device.frequencyKHz ?? 0)
        let ch = device.channel ?? 1
        if let freqKHz = table.frequency(bank: bank, channel: ch) {
            updateDevice(device.id) { $0.bank = bank; $0.channel = ch }
            setDeviceFrequency(device, frequencyKHz: freqKHz)
        } else if let freqKHz = table.frequency(bank: bank, channel: 1) {
            updateDevice(device.id) { $0.bank = bank; $0.channel = 1 }
            setDeviceFrequency(device, frequencyKHz: freqKHz)
        } else {
            updateDevice(device.id) { $0.bank = bank }
            statusMessage = "No frequency for Bank \(bank)"
        }
    }

    func setDeviceChannel(_ device: SennheiserDevice, channel: Int) {
        let table = FrequencyTable.detectRange(frequencyKHz: device.frequencyKHz ?? 0)
        let bank = device.bank ?? 1
        if let freqKHz = table.frequency(bank: bank, channel: channel) {
            updateDevice(device.id) { $0.channel = channel }
            setDeviceFrequency(device, frequencyKHz: freqKHz)
        } else {
            updateDevice(device.id) { $0.channel = channel }
            statusMessage = "No frequency for Bank \(bank) Ch \(channel)"
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

    func setDeviceAutoLock(_ device: SennheiserDevice, locked: Bool) {
        updateDevice(device.id) { $0.autoLock = locked }
        binaryProtocol.setTxAutoLock(deviceIP: device.host, locked)
    }

    func setDeviceRfPower(_ device: SennheiserDevice, mW: Int) {
        updateDevice(device.id) { $0.rfPower = mW }
        binaryProtocol.setRfPower(deviceIP: device.host, mW: mW)
    }

    func setDeviceWarningAfPeak(_ device: SennheiserDevice, enabled: Bool) {
        updateDevice(device.id) { $0.warningAfPeak = enabled }
        binaryProtocol.setWarnAfPeak(deviceIP: device.host, enabled)
    }

    func setDeviceWarningRfMute(_ device: SennheiserDevice, enabled: Bool) {
        updateDevice(device.id) { $0.warningRfMute = enabled }
        binaryProtocol.setWarnRfMute(deviceIP: device.host, enabled)
    }

    func setRxAutoLock(_ device: SennheiserDevice, locked: Bool) {
        updateDevice(device.id) { $0.rxAutoLock = locked }
        binaryProtocol.setRxAutoLock(deviceIP: device.host, locked: locked)
    }

    func setRxBalance(_ device: SennheiserDevice, value: Int) {
        updateDevice(device.id) { $0.rxBalance = value }
        binaryProtocol.setRxBalance(deviceIP: device.host, value)
    }

    func setRxMode(_ device: SennheiserDevice, mode: SennheiserDevice.RxMode) {
        updateDevice(device.id) { $0.rxMode = mode }
        binaryProtocol.setRxMode(deviceIP: device.host, stereo: mode == .stereo)
    }

    func setRxLimiter(_ device: SennheiserDevice, value: Int) {
        updateDevice(device.id) { $0.rxLimiter = value }
        binaryProtocol.setRxLimiter(deviceIP: device.host, dB: value)
    }

    func setRxHighBoost(_ device: SennheiserDevice, enabled: Bool) {
        updateDevice(device.id) { $0.rxHighBoost = enabled }
        binaryProtocol.setRxHighBoost(deviceIP: device.host, enabled)
    }

    func setRxSquelch(_ device: SennheiserDevice, value: Int) {
        updateDevice(device.id) { $0.rxSquelch = value }
        binaryProtocol.setRxSquelch(deviceIP: device.host, dB: value)
    }

    // MARK: - RX Sync Enable/Ignore flags

    func setRxAutoLockSync(_ device: SennheiserDevice, enabled: Bool) {
        updateDevice(device.id) { $0.rxAutoLockSync = enabled }
        if enabled {
            binaryProtocol.setRxAutoLock(deviceIP: device.host, locked: device.rxAutoLock)
        } else {
            binaryProtocol.ignoreParameter(deviceIP: device.host, .rxAutoLock)
        }
    }

    func setRxBalanceSync(_ device: SennheiserDevice, enabled: Bool) {
        updateDevice(device.id) { $0.rxBalanceSync = enabled }
        if enabled {
            binaryProtocol.setRxBalance(deviceIP: device.host, device.rxBalance)
        } else {
            binaryProtocol.ignoreParameter(deviceIP: device.host, .rxBalance)
        }
    }

    func setRxModeSync(_ device: SennheiserDevice, enabled: Bool) {
        updateDevice(device.id) { $0.rxModeSync = enabled }
        if enabled {
            binaryProtocol.setRxMode(deviceIP: device.host, stereo: device.rxMode == .stereo)
        } else {
            binaryProtocol.ignoreParameter(deviceIP: device.host, .rxMode)
        }
    }

    func setRxLimiterSync(_ device: SennheiserDevice, enabled: Bool) {
        updateDevice(device.id) { $0.rxLimiterSync = enabled }
        if enabled {
            binaryProtocol.setRxLimiter(deviceIP: device.host, dB: device.rxLimiter)
        } else {
            binaryProtocol.ignoreParameter(deviceIP: device.host, .rxLimiter)
        }
    }

    func setRxHighBoostSync(_ device: SennheiserDevice, enabled: Bool) {
        updateDevice(device.id) { $0.rxHighBoostSync = enabled }
        if enabled {
            binaryProtocol.setRxHighBoost(deviceIP: device.host, device.rxHighBoost)
        } else {
            binaryProtocol.ignoreParameter(deviceIP: device.host, .rxHighBoost)
        }
    }

    func setRxSquelchSync(_ device: SennheiserDevice, enabled: Bool) {
        updateDevice(device.id) { $0.rxSquelchSync = enabled }
        if enabled {
            binaryProtocol.setRxSquelch(deviceIP: device.host, dB: device.rxSquelch)
        } else {
            binaryProtocol.ignoreParameter(deviceIP: device.host, .rxSquelch)
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
