import Foundation

class BinaryProtocol {
    static let shared = BinaryProtocol()

    private let port: UInt16 = 8133
    private let queue = DispatchQueue(label: "binary.protocol", qos: .userInitiated)
    private var fd: Int32 = -1
    private var localIP: String = ""
    private var keepaliveTimer: DispatchSourceTimer?
    private var receiveTimer: DispatchSourceTimer?

    private var devices: [String: DeviceEntry] = [:]

    private struct DeviceEntry {
        let ip: String
        let onStateUpdate: (DeviceState) -> Void
    }

    struct DeviceState {
        let name: String
        let frequencyKHz: Int
        let bank: Int
        let channel: Int
        let sensitivity: Int      // state[26]: index, dB = -42 + index*3
        let txMode: Int           // state[27]: 0=stereo, 1=mono (reversed from SSC)
        let txAutoLock: Bool      // state[34]: 0=unlocked, 1=locked
        let rfPower: Int          // state[36]: 0=10mW, 1=30mW, 2=50mW
        let warnAfPeak: Bool      // state[37]: 0=off, 1=on
        let warnRfMute: Bool      // state[38]: 0=off, 1=on
        let rxAutoLock: Int       // state[39]: 0=ignore, 1=unlocked, 2=locked
        let rxBalance: Int        // state[40]: raw value, 0x10=center
        let rxMode: Int           // state[41]: 1=stereo, 2=focus
        let rxLimiter: Int        // state[42]: raw value
        let rxHighBoost: Bool     // state[43]: 1=off, 2=on
        let rxSquelch: Int        // state[44]: raw value
        let raw: Data
    }

    // MARK: - Parameter positions

    enum Parameter: Int {
        case txAutoLock = 30   // state[34]
        case rfPower = 32      // state[36]
        case warnAfPeak = 33   // state[37]
        case warnRfMute = 34   // state[38]
        case rxAutoLock = 35   // state[39]
        case rxBalance = 36    // state[40]
        case rxMode = 37       // state[41]
        case rxLimiter = 38    // state[42]
        case rxHighBoost = 39  // state[43]
        case rxSquelch = 40    // state[44]

        var statePos: Int { rawValue + 4 }
    }

    // MARK: - Value encoding

    static func decodeSensitivity(_ val: UInt8) -> Int {
        return Int(val) * 3 - 42
    }

    static func encodeSensitivity(dB: Int) -> UInt8 {
        return UInt8(clamping: (dB + 42) / 3)
    }

    static func encodeRfPower(mW: Int) -> UInt8 {
        switch mW {
        case 10: return 0x00
        case 30: return 0x01
        case 50: return 0x02
        default: return 0x01
        }
    }

    static func decodeRfPower(_ val: UInt8) -> Int {
        switch val {
        case 0x00: return 10
        case 0x01: return 30
        case 0x02: return 50
        default: return 30
        }
    }

    static func encodeBalance(_ balance: Int) -> UInt8 {
        return UInt8(clamping: balance + 16)
    }

    static func decodeBalance(_ val: UInt8) -> Int {
        return Int(val) - 16
    }

    static func encodeSquelch(dB: Int) -> UInt8 {
        return UInt8(clamping: (dB - 3) / 2)
    }

    static func decodeSquelch(_ val: UInt8) -> Int {
        return Int(val) * 2 + 3
    }

    static func encodeLimiter(dB: Int) -> UInt8 {
        switch dB {
        case 0: return 0x01
        case -6: return 0x02
        case -12: return 0x03
        case -18: return 0x04
        default: return 0x01
        }
    }

    static func decodeLimiter(_ val: UInt8) -> Int {
        switch val {
        case 0x01: return 0
        case 0x02: return -6
        case 0x03: return -12
        case 0x04: return -18
        default: return 0
        }
    }

    // MARK: - Shared socket management

    private init() {}

    private func ensureSocket() -> Bool {
        if fd >= 0 { return true }

        fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return false }

        var reuseAddr: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))

        var tv = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var bindAddr = sockaddr_in()
        bindAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        bindAddr.sin_family = sa_family_t(AF_INET)
        bindAddr.sin_port = port.bigEndian
        bindAddr.sin_addr.s_addr = INADDR_ANY

        let bindResult = withUnsafePointer(to: &bindAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(fd); fd = -1; return false
        }

        startReceiving()
        startKeepalive()
        return true
    }

    func shutdown() {
        queue.sync {
            keepaliveTimer?.cancel()
            keepaliveTimer = nil
            receiveTimer?.cancel()
            receiveTimer = nil
            if fd >= 0 {
                Darwin.close(fd)
                fd = -1
            }
            devices.removeAll()
            localIP = ""
        }
    }

    // MARK: - Device registration

    func addDevice(ip: String, onStateUpdate: @escaping (DeviceState) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }

            if self.localIP.isEmpty {
                self.localIP = self.getLocalIP(for: ip)
            }
            guard !self.localIP.isEmpty else { return }
            guard self.ensureSocket() else { return }

            self.devices[ip] = DeviceEntry(ip: ip, onStateUpdate: onStateUpdate)
            self.sendHandshake(to: ip)
        }
    }

    func removeDevice(ip: String) {
        queue.async { [weak self] in
            self?.devices.removeValue(forKey: ip)
        }
    }

    func removeAllDevices() {
        queue.async { [weak self] in
            self?.devices.removeAll()
        }
    }

    // MARK: - Handshake (matching WSM's exact sequence)

    private func sendHandshake(to deviceIP: String) {
        let ipBytes = ipToBytes(localIP)

        var init_pkt = Data([0x4f, 0x1f, 0xf1, 0xca])
        init_pkt.append(contentsOf: ipBytes)
        init_pkt.append(contentsOf: ipBytes)
        init_pkt.append(contentsOf: [0x00, 0x00, 0x01, 0x01, 0x01, 0x01])

        var pkt11 = Data([0xa4, 0xfd, 0xf7, 0xca])
        pkt11.append(contentsOf: ipBytes)
        pkt11.append(contentsOf: [0x01, 0x01, 0x01])

        var pkt14 = Data([0x4c, 0x37, 0xca, 0xce])
        pkt14.append(contentsOf: ipBytes.reversed())
        pkt14.append(contentsOf: [0xff, 0xff, 0xff, 0xff, 0x01, 0x01])

        sendUDP(init_pkt, to: deviceIP)
        sendUDP(pkt11, to: deviceIP)
        sendUDP(init_pkt, to: deviceIP)
        sendUDP(pkt14, to: deviceIP)

        queue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.sendUDP(pkt11, to: deviceIP)
        }
    }

    // MARK: - Keepalive

    private func startKeepalive() {
        guard keepaliveTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: 5.0)
        var tick = 0
        timer.setEventHandler { [weak self] in
            guard let self = self, self.fd >= 0 else { return }
            let ipBytes = self.ipToBytes(self.localIP)

            let pkt11 = Data([0xa4, 0xfd, 0xf7, 0xca]) + Data(ipBytes) + Data([0x01, 0x01, 0x01])
            for ip in self.devices.keys {
                self.sendUDP(pkt11, to: ip)
            }

            tick += 1
            if tick % 2 == 0 {
                var pkt = Data([0x4f, 0x1f, 0xf1, 0xca])
                pkt.append(contentsOf: ipBytes)
                pkt.append(contentsOf: ipBytes)
                pkt.append(contentsOf: [0x01, 0x00, 0x01, 0x01, 0x01, 0x01])
                for ip in self.devices.keys {
                    self.sendUDP(pkt, to: ip)
                }
            }
        }
        timer.resume()
        keepaliveTimer = timer
    }

    // MARK: - Receiving

    private func startReceiving() {
        guard receiveTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 0.1)
        timer.setEventHandler { [weak self] in
            self?.drainReceive()
        }
        timer.resume()
        receiveTimer = timer
    }

    private func drainReceive() {
        var buf = [UInt8](repeating: 0, count: 2048)
        var srcAddr = sockaddr_in()
        var srcLen = socklen_t(MemoryLayout<sockaddr_in>.size)

        while true {
            srcLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &srcAddr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    recvfrom(fd, &buf, buf.count, MSG_DONTWAIT, sa, &srcLen)
                }
            }
            guard n > 0 else { break }

            let data = Data(buf[0..<n])
            if n >= 66 && data[0..<4] == Data([0xca, 0x80, 0x70, 0xcd]) {
                var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, &srcAddr.sin_addr, &ipBuf, socklen_t(INET_ADDRSTRLEN))
                let srcIP = String(cString: ipBuf)

                if let entry = devices[srcIP] {
                    let state = parseState(data)
                    entry.onStateUpdate(state)
                }
            }
        }
    }

    private func parseState(_ data: Data) -> DeviceState {
        let name = String(bytes: data[12..<20], encoding: .ascii)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        let freqBytes = data[20..<24]
        let frequencyKHz = Int(freqBytes[20]) | (Int(freqBytes[21]) << 8) | (Int(freqBytes[22]) << 16) | (Int(freqBytes[23]) << 24)

        return DeviceState(
            name: name,
            frequencyKHz: frequencyKHz,
            bank: Int(data[24]) + 1,
            channel: Int(data[25]),
            sensitivity: Self.decodeSensitivity(data[26]),
            txMode: Int(data[27]),
            txAutoLock: data[34] != 0,
            rfPower: Self.decodeRfPower(data[36]),
            warnAfPeak: data[37] != 0,
            warnRfMute: data[38] != 0,
            rxAutoLock: Int(data[39]),
            rxBalance: Self.decodeBalance(data[40]),
            rxMode: Int(data[41]),
            rxLimiter: Self.decodeLimiter(data[42]),
            rxHighBoost: data[43] == 0x02,
            rxSquelch: Self.decodeSquelch(data[44]),
            raw: data
        )
    }

    // MARK: - Send commands (targeted to specific device)

    func setParameter(deviceIP: String, _ param: Parameter, value: UInt8) {
        queue.async { [weak self] in
            self?.sendCommand(deviceIP: deviceIP, cmdPos: param.rawValue, value: value)
        }
    }

    func setRfPower(deviceIP: String, mW: Int) {
        setParameter(deviceIP: deviceIP, .rfPower, value: Self.encodeRfPower(mW: mW))
    }

    func setTxAutoLock(deviceIP: String, _ locked: Bool) {
        setParameter(deviceIP: deviceIP, .txAutoLock, value: locked ? 0x01 : 0x00)
    }

    func setWarnAfPeak(deviceIP: String, _ enabled: Bool) {
        setParameter(deviceIP: deviceIP, .warnAfPeak, value: enabled ? 0x01 : 0x00)
    }

    func setWarnRfMute(deviceIP: String, _ enabled: Bool) {
        setParameter(deviceIP: deviceIP, .warnRfMute, value: enabled ? 0x01 : 0x00)
    }

    func setRxAutoLock(deviceIP: String, locked: Bool) {
        setParameter(deviceIP: deviceIP, .rxAutoLock, value: locked ? 0x02 : 0x01)
    }

    func setRxBalance(deviceIP: String, _ balance: Int) {
        setParameter(deviceIP: deviceIP, .rxBalance, value: Self.encodeBalance(balance))
    }

    func setRxMode(deviceIP: String, stereo: Bool) {
        setParameter(deviceIP: deviceIP, .rxMode, value: stereo ? 0x01 : 0x02)
    }

    func setRxLimiter(deviceIP: String, dB: Int) {
        setParameter(deviceIP: deviceIP, .rxLimiter, value: Self.encodeLimiter(dB: dB))
    }

    func setRxHighBoost(deviceIP: String, _ enabled: Bool) {
        setParameter(deviceIP: deviceIP, .rxHighBoost, value: enabled ? 0x02 : 0x01)
    }

    func setRxSquelch(deviceIP: String, dB: Int) {
        setParameter(deviceIP: deviceIP, .rxSquelch, value: Self.encodeSquelch(dB: dB))
    }

    func ignoreParameter(deviceIP: String, _ param: Parameter) {
        setParameter(deviceIP: deviceIP, param, value: 0x00)
    }

    func requestState(deviceIP: String) {
        queue.async { [weak self] in
            guard let self = self, self.fd >= 0 else { return }
            let ipBytes = self.ipToBytes(self.localIP)
            var pkt11 = Data([0xa4, 0xfd, 0xf7, 0xca])
            pkt11.append(contentsOf: ipBytes)
            pkt11.append(contentsOf: [0x01, 0x01, 0x01])
            self.sendUDP(pkt11, to: deviceIP)
        }
    }

    // MARK: - Low-level

    private func sendCommand(deviceIP: String, cmdPos: Int, value: UInt8) {
        guard fd >= 0, cmdPos >= 30, cmdPos <= 40 else { return }
        let ipBytes = ipToBytes(localIP)

        var cmd = Data(count: 60)
        cmd[0] = 0xc1; cmd[1] = 0x80; cmd[2] = 0x70; cmd[3] = 0xcd
        cmd[4] = ipBytes[0]; cmd[5] = ipBytes[1]
        cmd[6] = ipBytes[2]; cmd[7] = ipBytes[3]
        cmd[cmdPos] = value
        cmd[41] = 0x01
        cmd[cmdPos + 19] = 0x01
        sendUDP(cmd, to: deviceIP)

        let pkt11 = Data([0xa4, 0xfd, 0xf7, 0xca]) + Data(ipBytes) + Data([0x01, 0x01, 0x01])
        queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.sendUDP(pkt11, to: deviceIP)
        }
    }

    private func sendUDP(_ data: Data, to deviceIP: String) {
        guard fd >= 0 else { return }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        inet_pton(AF_INET, deviceIP, &addr.sin_addr)

        data.withUnsafeBytes { buf in
            withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(fd, buf.baseAddress, buf.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    // MARK: - Helpers

    private func ipToBytes(_ ip: String) -> [UInt8] {
        ip.split(separator: ".").compactMap { UInt8($0) }
    }

    private func getLocalIP(for remoteIP: String) -> String {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return "" }
        defer { Darwin.close(fd) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        inet_pton(AF_INET, remoteIP, &addr.sin_addr)

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else { return "" }

        var localAddr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &localAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                getsockname(fd, sa, &len)
            }
        }

        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &localAddr.sin_addr, &buf, socklen_t(INET_ADDRSTRLEN))
        return String(cString: buf)
    }
}
