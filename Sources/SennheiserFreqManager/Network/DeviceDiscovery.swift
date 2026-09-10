import Foundation
import Network
import Combine

class DeviceDiscovery: NSObject, ObservableObject {
    @Published var discoveredDevices: [SennheiserDevice] = []

    private let sennheiserPort: UInt16 = 53213
    private let queue = DispatchQueue(label: "device.discovery", qos: .userInitiated)
    private var discoveredHosts: Set<String> = []
    private var isRunning = false

    func startBrowsing() {
        discoveredDevices.removeAll()
        discoveredHosts.removeAll()
        guard !isRunning else { return }
        isRunning = true

        queue.async { [weak self] in
            self?.runSubnetScan()
        }
    }

    func stopBrowsing() {
        isRunning = false
    }

    private func runSubnetScan() {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { isRunning = false; return }
        defer { close(fd) }

        // Non-blocking receive timeout
        var tv = timeval(tv_sec: 0, tv_usec: 100_000) // 100ms
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let command = "Name\r".data(using: .ascii)!
        let subnets = getLocalSubnets()

        // Send "Name\r" to every host in every subnet
        for subnet in subnets {
            let hosts = hostsInSubnet(ip: subnet.ip, mask: subnet.mask)
            for host in hosts {
                guard isRunning else { return }
                var addr = sockaddr_in()
                addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = sennheiserPort.bigEndian
                inet_pton(AF_INET, host, &addr.sin_addr)

                command.withUnsafeBytes { buf in
                    withUnsafePointer(to: &addr) { addrPtr in
                        addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                            sendto(fd, buf.baseAddress, buf.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                }
            }
        }

        // Collect responses for 2 seconds
        let deadline = Date().addingTimeInterval(2.0)
        var buf = [UInt8](repeating: 0, count: 1024)
        var srcAddr = sockaddr_in()
        var srcLen = socklen_t(MemoryLayout<sockaddr_in>.size)

        while Date() < deadline && isRunning {
            let n = withUnsafeMutablePointer(to: &srcAddr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    recvfrom(fd, &buf, buf.count, 0, sa, &srcLen)
                }
            }

            guard n > 0 else { continue }

            let response = String(bytes: buf[0..<n], encoding: .ascii)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard response.hasPrefix("Name ") else { continue }
            let deviceName = String(response.dropFirst(5))
            guard !deviceName.isEmpty else { continue }

            var hostBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &srcAddr.sin_addr, &hostBuf, socklen_t(INET_ADDRSTRLEN))
            let host = String(cString: hostBuf)

            guard !discoveredHosts.contains(host) else { continue }

            // Verify with Frequency command
            if verifyDevice(fd: fd, host: host) {
                discoveredHosts.insert(host)
                let device = SennheiserDevice(id: "senn-\(host)", name: deviceName, host: host)
                DispatchQueue.main.async { [weak self] in
                    self?.discoveredDevices.append(device)
                }
            }
        }

        isRunning = false
    }

    private func verifyDevice(fd: Int32, host: String) -> Bool {
        let command = "Frequency\r".data(using: .ascii)!
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = sennheiserPort.bigEndian
        inet_pton(AF_INET, host, &addr.sin_addr)

        command.withUnsafeBytes { buf in
            withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(fd, buf.baseAddress, buf.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        var recvBuf = [UInt8](repeating: 0, count: 1024)
        var srcAddr = sockaddr_in()
        var srcLen = socklen_t(MemoryLayout<sockaddr_in>.size)

        // Wait up to 500ms for response
        var tv = timeval(tv_sec: 0, tv_usec: 500_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let n = withUnsafeMutablePointer(to: &srcAddr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                recvfrom(fd, &recvBuf, recvBuf.count, 0, sa, &srcLen)
            }
        }

        // Restore short timeout
        tv = timeval(tv_sec: 0, tv_usec: 100_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        guard n > 0 else { return false }
        let response = String(bytes: recvBuf[0..<n], encoding: .ascii)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let parts = response.split(separator: " ")
        return parts.count >= 2 && parts[0] == "Frequency" && Int(parts[1]) != nil
    }

    private struct SubnetInfo {
        let ip: String
        let mask: String
    }

    private func hostsInSubnet(ip: String, mask: String) -> [String] {
        let ipParts = ip.split(separator: ".").compactMap { UInt32($0) }
        let maskParts = mask.split(separator: ".").compactMap { UInt32($0) }
        guard ipParts.count == 4, maskParts.count == 4 else { return [] }

        let ipVal = (ipParts[0] << 24) | (ipParts[1] << 16) | (ipParts[2] << 8) | ipParts[3]
        let maskVal = (maskParts[0] << 24) | (maskParts[1] << 16) | (maskParts[2] << 8) | maskParts[3]
        let network = ipVal & maskVal
        let hostBits = ~maskVal & 0xFFFFFFFF

        guard hostBits <= 65534 else { return [] }

        var hosts: [String] = []
        for i: UInt32 in 1..<hostBits {
            let target = network | i
            if target == ipVal { continue }
            hosts.append("\(target >> 24).\((target >> 16) & 0xFF).\((target >> 8) & 0xFF).\(target & 0xFF)")
        }
        return hosts
    }

    private func getLocalSubnets() -> [SubnetInfo] {
        var subnets: [SubnetInfo] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return subnets }
        defer { freeifaddrs(ifaddr) }

        var ptr = firstAddr
        while true {
            let flags = Int32(ptr.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            if isUp && !isLoopback && ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                var ipBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                var maskBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))

                if getnameinfo(ptr.pointee.ifa_addr, socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                               &ipBuf, socklen_t(ipBuf.count), nil, 0, NI_NUMERICHOST) == 0,
                   let netmask = ptr.pointee.ifa_netmask,
                   getnameinfo(netmask, socklen_t(netmask.pointee.sa_len),
                               &maskBuf, socklen_t(maskBuf.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: ipBuf)
                    let mask = String(cString: maskBuf)
                    if ip != "0.0.0.0" {
                        subnets.append(SubnetInfo(ip: ip, mask: mask))
                    }
                }
            }

            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }

        return subnets
    }
}
