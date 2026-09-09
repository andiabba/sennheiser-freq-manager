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
    private var cancellables = Set<AnyCancellable>()

    init() {
        deviceDiscovery.$discoveredDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                self?.devices = devices
            }
            .store(in: &cancellables)
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
        p.queryFrequency(device: device) { [weak self] r in
            if case .success(let v) = r { self?.mainUpdate(id) { $0.frequencyKHz = v } }
        }
        p.queryBank(device: device) { [weak self] r in
            if case .success(let v) = r { self?.mainUpdate(id) { $0.bank = v } }
        }
        p.queryChannel(device: device) { [weak self] r in
            if case .success(let v) = r { self?.mainUpdate(id) { $0.channel = v } }
        }
        p.querySensitivity(device: device) { [weak self] r in
            if case .success(let v) = r { self?.mainUpdate(id) { $0.sensitivity = v } }
        }
        p.queryMode(device: device) { [weak self] r in
            if case .success(let v) = r { self?.mainUpdate(id) { $0.mode = v } }
        }
        p.queryAutoLock(device: device) { [weak self] r in
            if case .success(let v) = r { self?.mainUpdate(id) { $0.autoLock = v } }
        }
        p.queryMute(device: device) { [weak self] r in
            if case .success(let v) = r { self?.mainUpdate(id) { $0.rfMute = v } }
        }
        p.queryRfPower(device: device) { [weak self] r in
            if case .success(let v) = r { self?.mainUpdate(id) { $0.rfPower = v } }
        }
        p.queryWarningAfPeak(device: device) { [weak self] r in
            if case .success(let v) = r { self?.mainUpdate(id) { $0.warningAfPeak = v } }
        }
        p.queryWarningRfMute(device: device) { [weak self] r in
            if case .success(let v) = r { self?.mainUpdate(id) { $0.warningRfMute = v } }
        }
        p.queryRxAutoLock(device: device) { [weak self] r in
            if case .success(let v) = r { self?.mainUpdate(id) { $0.rxAutoLock = v } }
        }
        p.queryRxBalance(device: device) { [weak self] r in
            if case .success(let v) = r { self?.mainUpdate(id) { $0.rxBalance = v } }
        }
        p.queryRxMode(device: device) { [weak self] r in
            if case .success(let v) = r { self?.mainUpdate(id) { $0.rxMode = v } }
        }
        p.queryRxLimiter(device: device) { [weak self] r in
            if case .success(let v) = r { self?.mainUpdate(id) { $0.rxLimiter = v } }
        }
        p.queryRxHighBoost(device: device) { [weak self] r in
            if case .success(let v) = r { self?.mainUpdate(id) { $0.rxHighBoost = v } }
        }
        p.queryRxSquelch(device: device) { [weak self] r in
            if case .success(let v) = r { self?.mainUpdate(id) { $0.rxSquelch = v } }
        }
    }

    // MARK: - Set individual parameters

    func setDeviceName(_ device: SennheiserDevice, name: String) {
        sennheiserProtocol.setName(device: device, name: name) { [weak self] r in
            if case .success = r {
                self?.mainUpdate(device.id) { $0.name = name }
                DispatchQueue.main.async { self?.statusMessage = "Name set to \(name)" }
            }
        }
    }

    func setDeviceFrequency(_ device: SennheiserDevice, frequencyKHz: Int) {
        sennheiserProtocol.setFrequency(device: device, frequencyKHz: frequencyKHz) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.updateDevice(device.id) { $0.frequencyKHz = frequencyKHz }
                    let mhz = Double(frequencyKHz) / 1000.0
                    self?.statusMessage = "Frequency set to \(String(format: "%.3f MHz", mhz))"
                case .failure(let error):
                    self?.statusMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    func setDeviceBank(_ device: SennheiserDevice, bank: Int) {
        sennheiserProtocol.setBank(device: device, bank: bank) { [weak self] r in
            if case .success = r {
                self?.mainUpdate(device.id) { $0.bank = bank }
                DispatchQueue.main.async { self?.statusMessage = "Bank set to \(bank)" }
            }
        }
    }

    func setDeviceChannel(_ device: SennheiserDevice, channel: Int) {
        sennheiserProtocol.setChannel(device: device, channel: channel) { [weak self] r in
            if case .success = r {
                self?.mainUpdate(device.id) { $0.channel = channel }
                DispatchQueue.main.async { self?.statusMessage = "Channel set to \(channel)" }
            }
        }
    }

    func setDeviceSensitivity(_ device: SennheiserDevice, dB: Int) {
        sennheiserProtocol.setSensitivity(device: device, dB: dB) { [weak self] r in
            if case .success = r {
                self?.mainUpdate(device.id) { $0.sensitivity = dB }
                DispatchQueue.main.async { self?.statusMessage = "Sensitivity set to \(dB) dB" }
            }
        }
    }

    func setDeviceMode(_ device: SennheiserDevice, mode: SennheiserDevice.AudioMode) {
        sennheiserProtocol.setMode(device: device, mode: mode) { [weak self] r in
            if case .success = r {
                self?.mainUpdate(device.id) { $0.mode = mode }
                DispatchQueue.main.async { self?.statusMessage = "Mode set to \(mode.rawValue)" }
            }
        }
    }

    func setDeviceAutoLock(_ device: SennheiserDevice, locked: Bool) {
        sennheiserProtocol.setAutoLock(device: device, locked: locked) { [weak self] r in
            if case .success = r {
                self?.mainUpdate(device.id) { $0.autoLock = locked }
                DispatchQueue.main.async { self?.statusMessage = locked ? "Locked" : "Unlocked" }
            }
        }
    }

    func setDeviceMute(_ device: SennheiserDevice, muted: Bool) {
        sennheiserProtocol.setMute(device: device, muted: muted) { [weak self] r in
            if case .success = r {
                self?.mainUpdate(device.id) { $0.rfMute = muted }
                DispatchQueue.main.async { self?.statusMessage = muted ? "RF Muted" : "RF Unmuted" }
            }
        }
    }

    func setDeviceRfPower(_ device: SennheiserDevice, mW: Int) {
        sennheiserProtocol.setRfPower(device: device, mW: mW) { [weak self] r in
            if case .success = r {
                self?.mainUpdate(device.id) { $0.rfPower = mW }
                DispatchQueue.main.async { self?.statusMessage = "RF Power set to \(mW) mW" }
            }
        }
    }

    func setDeviceWarningAfPeak(_ device: SennheiserDevice, enabled: Bool) {
        sennheiserProtocol.setWarningAfPeak(device: device, enabled: enabled) { [weak self] r in
            if case .success = r {
                self?.mainUpdate(device.id) { $0.warningAfPeak = enabled }
            }
        }
    }

    func setDeviceWarningRfMute(_ device: SennheiserDevice, enabled: Bool) {
        sennheiserProtocol.setWarningRfMute(device: device, enabled: enabled) { [weak self] r in
            if case .success = r {
                self?.mainUpdate(device.id) { $0.warningRfMute = enabled }
            }
        }
    }

    // MARK: - RX Sync Settings

    func setRxAutoLock(_ device: SennheiserDevice, locked: Bool) {
        sennheiserProtocol.setRxAutoLock(device: device, locked: locked) { [weak self] r in
            if case .success = r {
                self?.mainUpdate(device.id) { $0.rxAutoLock = locked }
            }
        }
    }

    func setRxBalance(_ device: SennheiserDevice, value: Int) {
        sennheiserProtocol.setRxBalance(device: device, value: value) { [weak self] r in
            if case .success = r {
                self?.mainUpdate(device.id) { $0.rxBalance = value }
                DispatchQueue.main.async { self?.statusMessage = "Balance set to \(value)" }
            }
        }
    }

    func setRxMode(_ device: SennheiserDevice, mode: SennheiserDevice.AudioMode) {
        sennheiserProtocol.setRxMode(device: device, mode: mode) { [weak self] r in
            if case .success = r {
                self?.mainUpdate(device.id) { $0.rxMode = mode }
                DispatchQueue.main.async { self?.statusMessage = "RX Mode set to \(mode.rawValue)" }
            }
        }
    }

    func setRxLimiter(_ device: SennheiserDevice, enabled: Bool) {
        sennheiserProtocol.setRxLimiter(device: device, enabled: enabled) { [weak self] r in
            if case .success = r {
                self?.mainUpdate(device.id) { $0.rxLimiter = enabled }
            }
        }
    }

    func setRxHighBoost(_ device: SennheiserDevice, enabled: Bool) {
        sennheiserProtocol.setRxHighBoost(device: device, enabled: enabled) { [weak self] r in
            if case .success = r {
                self?.mainUpdate(device.id) { $0.rxHighBoost = enabled }
            }
        }
    }

    func setRxSquelch(_ device: SennheiserDevice, value: Int) {
        sennheiserProtocol.setRxSquelch(device: device, value: value) { [weak self] r in
            if case .success = r {
                self?.mainUpdate(device.id) { $0.rxSquelch = value }
                DispatchQueue.main.async { self?.statusMessage = "Squelch set to \(value)" }
            }
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
