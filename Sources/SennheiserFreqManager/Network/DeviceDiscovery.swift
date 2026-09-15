import Foundation
import Network
import Combine

class DeviceDiscovery: NSObject, ObservableObject {
    @Published var discoveredDevices: [SennheiserDevice] = []

    private let binaryPort: UInt16 = 8133
    private let multicastGroup = "224.0.0.251"
    private let queue = DispatchQueue(label: "device.discovery", qos: .userInitiated)
    private var discoveredHosts: Set<String> = []
    private var isRunning = false

    func startBrowsing() {
        discoveredDevices.removeAll()
        discoveredHosts.removeAll()
        guard !isRunning else { return }
        isRunning = true

        queue.async { [weak self] in
            self?.runMulticastDiscovery()
        }
    }

    func stopBrowsing() {
        isRunning = false
    }

    private func runMulticastDiscovery() {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { isRunning = false; return }
        defer { close(fd) }

        var reuseAddr: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))

        var tv = timeval(tv_sec: 0, tv_usec: 200_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var ttl: UInt8 = 1
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))

        var bindAddr = sockaddr_in()
        bindAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        bindAddr.sin_family = sa_family_t(AF_INET)
        bindAddr.sin_port = binaryPort.bigEndian
        bindAddr.sin_addr.s_addr = INADDR_ANY

        let bindResult = withUnsafePointer(to: &bindAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { isRunning = false; return }

        let packet = buildDevInfoPacket()
        let localIPs = getLocalInterfaceIPs()

        var mcastAddr = sockaddr_in()
        mcastAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        mcastAddr.sin_family = sa_family_t(AF_INET)
        mcastAddr.sin_port = binaryPort.bigEndian
        inet_pton(AF_INET, multicastGroup, &mcastAddr.sin_addr)

        for round in 0..<3 {
            guard isRunning else { break }
            if round > 0 { usleep(300_000) }

            // Send multicast on each interface
            for ip in localIPs {
                var ifAddr = in_addr()
                inet_pton(AF_INET, ip, &ifAddr)
                setsockopt(fd, IPPROTO_IP, IP_MULTICAST_IF, &ifAddr, socklen_t(MemoryLayout<in_addr>.size))

                packet.withUnsafeBytes { buf in
                    withUnsafePointer(to: &mcastAddr) { addrPtr in
                        addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                            sendto(fd, buf.baseAddress, buf.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                }
            }

            collectResponses(fd: fd, duration: 0.8)
        }

        isRunning = false
    }

    private func buildDevInfoPacket() -> Data {
        let payload = "[servicecommand]devinfo\r\n"
        let payloadData = payload.data(using: .ascii)!

        var packet = Data(count: 1035)
        packet[0] = 0x12; packet[1] = 0x07; packet[2] = 0x06; packet[3] = 0x20
        packet[4] = 0x00; packet[5] = 0x00; packet[6] = 0x19; packet[7] = 0x00

        for (i, byte) in payloadData.enumerated() {
            packet[8 + i] = byte
        }

        packet[1033] = 0x01
        packet[1034] = 0x01

        return packet
    }

    private func collectResponses(fd: Int32, duration: TimeInterval) {
        let deadline = Date().addingTimeInterval(duration)
        var buf = [UInt8](repeating: 0, count: 2048)
        var srcAddr = sockaddr_in()
        var srcLen = socklen_t(MemoryLayout<sockaddr_in>.size)

        while Date() < deadline && isRunning {
            srcLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &srcAddr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    recvfrom(fd, &buf, buf.count, 0, sa, &srcLen)
                }
            }

            guard n > 0 else { continue }

            let data = Data(buf[0..<n])
            guard let info = parseDevInfoResponse(data) else { continue }
            guard !discoveredHosts.contains(info.ip) else { continue }

            discoveredHosts.insert(info.ip)
            let device = SennheiserDevice(id: "senn-\(info.ip)", name: info.model, host: info.ip)
            DispatchQueue.main.async { [weak self] in
                self?.discoveredDevices.append(device)
            }
        }
    }

    private struct DevInfo {
        let model: String
        let macAddress: String
        let ip: String
    }

    private func parseDevInfoResponse(_ data: Data) -> DevInfo? {
        guard let str = String(data: data, encoding: .ascii) else { return nil }
        guard str.contains("Model=") && str.contains("IPA=") else { return nil }

        var model = ""
        var macAddress = ""
        var ip = ""

        // Extract key=value pairs using regex-like search since response has
        // non-printable prefixes (e.g. "%Model=SR-IEMG4")
        let cleaned = str.replacingOccurrences(of: "\0", with: " ")
        for keyword in ["Model", "ID", "IPA"] {
            guard let range = cleaned.range(of: "\(keyword)=") else { continue }
            let after = cleaned[range.upperBound...]
            let value = String(after.prefix(while: { $0 != " " && $0 != "\0" && $0 != "\r" && $0 != "\n" }))
            switch keyword {
            case "Model": model = value
            case "ID": macAddress = value
            case "IPA": ip = value
            default: break
            }
        }

        guard !ip.isEmpty else { return nil }
        if model.isEmpty { model = "Sennheiser" }

        return DevInfo(model: model, macAddress: macAddress, ip: ip)
    }

    private func getLocalInterfaceIPs() -> [String] {
        var ips: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return ips }
        defer { freeifaddrs(ifaddr) }

        var ptr = firstAddr
        while true {
            let flags = Int32(ptr.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            if isUp && !isLoopback && ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                var ipBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(ptr.pointee.ifa_addr, socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                               &ipBuf, socklen_t(ipBuf.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: ipBuf)
                    if ip != "0.0.0.0" {
                        ips.append(ip)
                    }
                }
            }

            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }

        return ips
    }
}
