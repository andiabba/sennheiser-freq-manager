import Foundation
import Combine

class AppState: ObservableObject {
    @Published var devices: [SennheiserDevice] = []
    @Published var showFile: WWBShowFile?
    @Published var assignments: [String: String] = [:]  // WWB entry ID -> device ID
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
                    if let idx = self?.devices.firstIndex(where: { $0.id == device.id }) {
                        self?.devices[idx].frequencyKHz = entry.frequencyKHz
                    }
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

    func queryDeviceState(_ device: SennheiserDevice) {
        sennheiserProtocol.queryFrequency(device: device) { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let freqKHz) = result,
                   let idx = self?.devices.firstIndex(where: { $0.id == device.id }) {
                    self?.devices[idx].frequencyKHz = freqKHz
                }
            }
        }
        sennheiserProtocol.queryName(device: device) { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let name) = result,
                   let idx = self?.devices.firstIndex(where: { $0.id == device.id }) {
                    self?.devices[idx].name = name
                }
            }
        }
        sennheiserProtocol.querySensitivity(device: device) { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let val) = result,
                   let idx = self?.devices.firstIndex(where: { $0.id == device.id }) {
                    self?.devices[idx].sensitivity = val
                }
            }
        }
        sennheiserProtocol.queryMute(device: device) { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let muted) = result,
                   let idx = self?.devices.firstIndex(where: { $0.id == device.id }) {
                    self?.devices[idx].muted = muted
                }
            }
        }
        sennheiserProtocol.queryMode(device: device) { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let mode) = result,
                   let idx = self?.devices.firstIndex(where: { $0.id == device.id }) {
                    self?.devices[idx].mode = mode
                }
            }
        }
    }

    func setDeviceName(_ device: SennheiserDevice, name: String) {
        sennheiserProtocol.setName(device: device, name: name) { [weak self] result in
            DispatchQueue.main.async {
                if case .success = result,
                   let idx = self?.devices.firstIndex(where: { $0.id == device.id }) {
                    self?.devices[idx].name = name
                    self?.statusMessage = "Name set to \(name)"
                }
            }
        }
    }

    func setDeviceFrequency(_ device: SennheiserDevice, frequencyKHz: Int) {
        sennheiserProtocol.setFrequency(device: device, frequencyKHz: frequencyKHz) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    if let idx = self?.devices.firstIndex(where: { $0.id == device.id }) {
                        self?.devices[idx].frequencyKHz = frequencyKHz
                    }
                    let mhz = Double(frequencyKHz) / 1000.0
                    self?.statusMessage = "Frequency set to \(String(format: "%.3f MHz", mhz))"
                case .failure(let error):
                    self?.statusMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    func setDeviceMute(_ device: SennheiserDevice, muted: Bool) {
        sennheiserProtocol.setMute(device: device, muted: muted) { [weak self] result in
            DispatchQueue.main.async {
                if case .success = result,
                   let idx = self?.devices.firstIndex(where: { $0.id == device.id }) {
                    self?.devices[idx].muted = muted
                    self?.statusMessage = muted ? "Muted" : "Unmuted"
                }
            }
        }
    }

    func setDeviceSensitivity(_ device: SennheiserDevice, dB: Int) {
        sennheiserProtocol.setSensitivity(device: device, dB: dB) { [weak self] result in
            DispatchQueue.main.async {
                if case .success = result,
                   let idx = self?.devices.firstIndex(where: { $0.id == device.id }) {
                    self?.devices[idx].sensitivity = dB
                    self?.statusMessage = "Sensitivity set to \(dB) dB"
                }
            }
        }
    }

    func setDeviceMode(_ device: SennheiserDevice, mode: SennheiserDevice.AudioMode) {
        sennheiserProtocol.setMode(device: device, mode: mode) { [weak self] result in
            DispatchQueue.main.async {
                if case .success = result,
                   let idx = self?.devices.firstIndex(where: { $0.id == device.id }) {
                    self?.devices[idx].mode = mode
                    self?.statusMessage = "Mode set to \(mode.rawValue)"
                }
            }
        }
    }
}
