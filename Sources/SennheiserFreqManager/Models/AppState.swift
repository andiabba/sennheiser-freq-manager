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
    }
}
