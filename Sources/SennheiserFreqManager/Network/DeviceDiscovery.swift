import Foundation
import Combine

class DeviceDiscovery: NSObject, ObservableObject {
    @Published var discoveredDevices: [SennheiserDevice] = []

    private var browser: NetServiceBrowser?
    private var services: [NetService] = []
    private var resolving: [NetService] = []

    func startBrowsing() {
        discoveredDevices.removeAll()
        services.removeAll()

        browser = NetServiceBrowser()
        browser?.delegate = self
        // Sennheiser ew G3/G4 use mDNS — the service type used by WSM
        browser?.searchForServices(ofType: "_sennheiser._udp.", inDomain: "local.")
    }

    func stopBrowsing() {
        browser?.stop()
        browser = nil
        resolving.forEach { $0.stop() }
        resolving.removeAll()
    }

    private func resolveService(_ service: NetService) {
        service.delegate = self
        service.resolve(withTimeout: 5.0)
        resolving.append(service)
    }
}

extension DeviceDiscovery: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.append(service)
        resolveService(service)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services.removeAll { $0 == service }
        DispatchQueue.main.async {
            self.discoveredDevices.removeAll { $0.name == service.name }
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        // mDNS service type may not match — try alternative
        let altBrowser = NetServiceBrowser()
        altBrowser.delegate = self
        altBrowser.searchForServices(ofType: "_ewg4._udp.", inDomain: "local.")
    }
}

extension DeviceDiscovery: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let addresses = sender.addresses else { return }

        for addressData in addresses {
            let hostname = extractHostname(from: addressData)
            if let hostname = hostname {
                let device = SennheiserDevice(
                    id: "\(sender.name)-\(hostname)",
                    name: sender.name,
                    host: hostname
                )
                DispatchQueue.main.async {
                    if !self.discoveredDevices.contains(where: { $0.host == hostname }) {
                        self.discoveredDevices.append(device)
                    }
                }
                break
            }
        }

        resolving.removeAll { $0 == sender }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        resolving.removeAll { $0 == sender }
    }

    private func extractHostname(from addressData: Data) -> String? {
        addressData.withUnsafeBytes { ptr -> String? in
            guard let sockaddr = ptr.baseAddress?.assumingMemoryBound(to: sockaddr.self) else { return nil }
            if sockaddr.pointee.sa_family == UInt8(AF_INET) {
                var addr = sockaddr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, &addr.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN))
                return String(cString: buffer)
            }
            return nil
        }
    }
}
