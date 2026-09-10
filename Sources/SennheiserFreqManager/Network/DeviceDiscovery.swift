import Foundation
import Network
import Combine

class DeviceDiscovery: NSObject, ObservableObject {
    @Published var discoveredDevices: [SennheiserDevice] = []

    private let sennheiserPort: UInt16 = 53213
    private var listener: NWListener?
    private var broadcastConnection: NWConnection?
    private let queue = DispatchQueue(label: "device.discovery", qos: .userInitiated)
    private var discoveredHosts: Set<String> = []

    func startBrowsing() {
        discoveredDevices.removeAll()
        discoveredHosts.removeAll()

        startListener()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.sendBroadcast()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.sendBroadcast()
        }
    }

    func stopBrowsing() {
        listener?.cancel()
        listener = nil
        broadcastConnection?.cancel()
        broadcastConnection = nil
    }

    private func startListener() {
        listener?.cancel()

        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        params.requiredInterfaceType = .wifi

        do {
            listener = try NWListener(using: params, on: NWEndpoint.Port(integerLiteral: sennheiserPort))
        } catch {
            // Try without specific port — just listen for broadcast responses
            do {
                listener = try NWListener(using: params)
            } catch {
                return
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleIncoming(connection)
        }
        listener?.start(queue: queue)
    }

    private func handleIncoming(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receiveMessage { [weak self] data, _, _, _ in
            if let data = data,
               let response = String(data: data, encoding: .ascii) {
                self?.parseResponse(response, from: connection.currentPath?.remoteEndpoint)
            }
            connection.cancel()
        }
    }

    private func sendBroadcast() {
        let interfaces = getLocalBroadcastAddresses()

        for broadcastAddr in interfaces {
            let host = NWEndpoint.Host(broadcastAddr)
            let port = NWEndpoint.Port(integerLiteral: sennheiserPort)

            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
                ip.disableMulticastLoopback = true
            }

            let connection = NWConnection(host: host, port: port, using: params)
            connection.start(queue: queue)

            connection.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                if case .ready = state {
                    let command = "Name\r"
                    if let data = command.data(using: .ascii) {
                        connection.send(content: data, completion: .contentProcessed { _ in })
                    }

                    self.receiveResponses(on: connection)
                }
            }
        }

        // Also try direct broadcast to 255.255.255.255
        sendDirectBroadcast()
    }

    private func sendDirectBroadcast() {
        let host = NWEndpoint.Host("255.255.255.255")
        let port = NWEndpoint.Port(integerLiteral: sennheiserPort)

        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        let connection = NWConnection(host: host, port: port, using: params)
        connection.start(queue: queue)

        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            if case .ready = state {
                let command = "Name\r"
                if let data = command.data(using: .ascii) {
                    connection.send(content: data, completion: .contentProcessed { _ in })
                }
                self.receiveResponses(on: connection)
            }
        }
    }

    private func receiveResponses(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self = self else { return }

            if let data = data,
               let response = String(data: data, encoding: .ascii) {
                self.parseResponse(response, from: connection.currentPath?.remoteEndpoint)
            }

            if error == nil {
                self.receiveResponses(on: connection)
            }
        }
    }

    private func parseResponse(_ response: String, from endpoint: NWEndpoint?) {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Only accept valid Sennheiser Media Control Protocol responses
        guard trimmed.hasPrefix("Name ") else { return }
        let deviceName = String(trimmed.dropFirst(5))
        guard !deviceName.isEmpty else { return }

        guard let host = extractHost(from: endpoint) else { return }

        // Verify with a second command before adding
        verifyDevice(host: host, name: deviceName)
    }

    private func verifyDevice(host: String, name: String) {
        let endpoint = NWEndpoint.Host(host)
        let port = NWEndpoint.Port(integerLiteral: sennheiserPort)
        let connection = NWConnection(host: endpoint, port: port, using: .udp)
        connection.start(queue: queue)

        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            if case .ready = state {
                let command = "Frequency\r"
                if let data = command.data(using: .ascii) {
                    connection.send(content: data, completion: .contentProcessed { _ in })
                }

                connection.receiveMessage { data, _, _, _ in
                    defer { connection.cancel() }
                    guard let data = data,
                          let response = String(data: data, encoding: .ascii) else { return }
                    let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

                    // Valid Sennheiser device responds with "Frequency <kHz>"
                    guard trimmed.hasPrefix("Frequency "),
                          let _ = Int(trimmed.dropFirst(10)) else { return }

                    self.queue.async {
                        guard !self.discoveredHosts.contains(host) else { return }
                        self.discoveredHosts.insert(host)

                        let device = SennheiserDevice(
                            id: "senn-\(host)",
                            name: name,
                            host: host
                        )

                        DispatchQueue.main.async {
                            self.discoveredDevices.append(device)
                        }
                    }
                }
            }
        }
    }

    private func extractHost(from endpoint: NWEndpoint?) -> String? {
        guard let endpoint = endpoint else { return nil }
        switch endpoint {
        case .hostPort(let host, _):
            switch host {
            case .ipv4(let addr):
                return "\(addr)"
            case .ipv6(let addr):
                return "\(addr)"
            case .name(let name, _):
                return name
            @unknown default:
                return nil
            }
        default:
            return nil
        }
    }

    private func getLocalBroadcastAddresses() -> [String] {
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return addresses }
        defer { freeifaddrs(ifaddr) }

        var ptr = firstAddr
        while true {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee

            if addr.sa_family == UInt8(AF_INET) && (flags & IFF_BROADCAST) != 0 {
                if let broadcastAddr = ptr.pointee.ifa_dstaddr {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(broadcastAddr, socklen_t(broadcastAddr.pointee.sa_len),
                                   &hostname, socklen_t(hostname.count),
                                   nil, 0, NI_NUMERICHOST) == 0 {
                        let addr = String(cString: hostname)
                        if addr != "0.0.0.0" {
                            addresses.append(addr)
                        }
                    }
                }
            }

            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }

        return addresses
    }
}
