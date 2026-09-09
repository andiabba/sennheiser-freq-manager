import Foundation
import Network

class SennheiserProtocol {
    private let queue = DispatchQueue(label: "sennheiser.protocol", qos: .userInitiated)
    private var connections: [String: NWConnection] = [:]

    private func getConnection(for device: SennheiserDevice) -> NWConnection {
        if let existing = connections[device.id], existing.state == .ready {
            return existing
        }

        let host = NWEndpoint.Host(device.host)
        let port = NWEndpoint.Port(integerLiteral: UInt16(device.port))
        let params = NWParameters.udp
        let connection = NWConnection(host: host, port: port, using: params)

        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                self?.connections.removeValue(forKey: device.id)
            }
        }

        connection.start(queue: queue)
        connections[device.id] = connection
        return connection
    }

    private func sendCommand(device: SennheiserDevice, command: String, completion: @escaping (Result<String, Error>) -> Void) {
        let connection = getConnection(for: device)
        let message = command + "\r"
        guard let data = message.data(using: .ascii) else {
            completion(.failure(ProtocolError.encodingFailed))
            return
        }

        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                completion(.failure(error))
                return
            }

            connection.receiveMessage { data, _, _, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                guard let data = data, let response = String(data: data, encoding: .ascii) else {
                    completion(.failure(ProtocolError.noResponse))
                    return
                }
                let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
                completion(.success(trimmed))
            }
        })
    }

    // MARK: - Generic query/set helpers

    private func queryInt(device: SennheiserDevice, command: String, completion: @escaping (Result<Int, Error>) -> Void) {
        sendCommand(device: device, command: command) { result in
            switch result {
            case .success(let response):
                let parts = response.split(separator: " ")
                if parts.count >= 2, let val = Int(parts[1]) {
                    completion(.success(val))
                } else {
                    completion(.failure(ProtocolError.parseError(response)))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func queryBool(device: SennheiserDevice, command: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        sendCommand(device: device, command: command) { result in
            switch result {
            case .success(let response):
                let parts = response.split(separator: " ")
                if parts.count >= 2 {
                    completion(.success(parts[1] == "1"))
                } else {
                    completion(.failure(ProtocolError.parseError(response)))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func setInt(device: SennheiserDevice, command: String, value: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        sendCommand(device: device, command: "\(command) \(value)") { result in
            completion(result.map { _ in () })
        }
    }

    private func setBool(device: SennheiserDevice, command: String, value: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        sendCommand(device: device, command: "\(command) \(value ? 1 : 0)") { result in
            completion(result.map { _ in () })
        }
    }

    // MARK: - Name

    func queryName(device: SennheiserDevice, completion: @escaping (Result<String, Error>) -> Void) {
        sendCommand(device: device, command: "Name") { result in
            switch result {
            case .success(let response):
                if response.hasPrefix("Name ") {
                    completion(.success(String(response.dropFirst(5))))
                } else {
                    completion(.failure(ProtocolError.parseError(response)))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func setName(device: SennheiserDevice, name: String, completion: @escaping (Result<Void, Error>) -> Void) {
        sendCommand(device: device, command: "Name \(name)") { result in
            completion(result.map { _ in () })
        }
    }

    // MARK: - Frequency / Bank / Channel

    func queryFrequency(device: SennheiserDevice, completion: @escaping (Result<Int, Error>) -> Void) {
        queryInt(device: device, command: "Frequency", completion: completion)
    }

    func setFrequency(device: SennheiserDevice, frequencyKHz: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        sendCommand(device: device, command: "Frequency \(frequencyKHz)") { result in
            switch result {
            case .success(let response):
                if response.hasPrefix("Frequency") {
                    completion(.success(()))
                } else {
                    completion(.failure(ProtocolError.unexpectedResponse(response)))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func queryBank(device: SennheiserDevice, completion: @escaping (Result<Int, Error>) -> Void) {
        queryInt(device: device, command: "Bank", completion: completion)
    }

    func setBank(device: SennheiserDevice, bank: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        setInt(device: device, command: "Bank", value: bank, completion: completion)
    }

    func queryChannel(device: SennheiserDevice, completion: @escaping (Result<Int, Error>) -> Void) {
        queryInt(device: device, command: "Channel", completion: completion)
    }

    func setChannel(device: SennheiserDevice, channel: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        setInt(device: device, command: "Channel", value: channel, completion: completion)
    }

    // MARK: - TX Settings

    func querySensitivity(device: SennheiserDevice, completion: @escaping (Result<Int, Error>) -> Void) {
        queryInt(device: device, command: "Sensitivity", completion: completion)
    }

    func setSensitivity(device: SennheiserDevice, dB: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        setInt(device: device, command: "Sensitivity", value: max(-42, min(0, dB)), completion: completion)
    }

    func queryMode(device: SennheiserDevice, completion: @escaping (Result<SennheiserDevice.TxMode, Error>) -> Void) {
        queryInt(device: device, command: "Mode") { result in
            completion(result.map { SennheiserDevice.TxMode(protocolValue: $0) })
        }
    }

    func setMode(device: SennheiserDevice, mode: SennheiserDevice.TxMode, completion: @escaping (Result<Void, Error>) -> Void) {
        setInt(device: device, command: "Mode", value: mode.protocolValue, completion: completion)
    }

    func queryAutoLock(device: SennheiserDevice, completion: @escaping (Result<Bool, Error>) -> Void) {
        queryBool(device: device, command: "Lock", completion: completion)
    }

    func setAutoLock(device: SennheiserDevice, locked: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        setBool(device: device, command: "Lock", value: locked, completion: completion)
    }

    func queryMute(device: SennheiserDevice, completion: @escaping (Result<Bool, Error>) -> Void) {
        queryBool(device: device, command: "Mute", completion: completion)
    }

    func setMute(device: SennheiserDevice, muted: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        setBool(device: device, command: "Mute", value: muted, completion: completion)
    }

    func queryRfPower(device: SennheiserDevice, completion: @escaping (Result<Int, Error>) -> Void) {
        queryInt(device: device, command: "RfPower", completion: completion)
    }

    func setRfPower(device: SennheiserDevice, mW: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        setInt(device: device, command: "RfPower", value: mW, completion: completion)
    }

    func queryWarningAfPeak(device: SennheiserDevice, completion: @escaping (Result<Bool, Error>) -> Void) {
        queryBool(device: device, command: "WarnPeak", completion: completion)
    }

    func setWarningAfPeak(device: SennheiserDevice, enabled: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        setBool(device: device, command: "WarnPeak", value: enabled, completion: completion)
    }

    func queryWarningRfMute(device: SennheiserDevice, completion: @escaping (Result<Bool, Error>) -> Void) {
        queryBool(device: device, command: "WarnMute", completion: completion)
    }

    func setWarningRfMute(device: SennheiserDevice, enabled: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        setBool(device: device, command: "WarnMute", value: enabled, completion: completion)
    }

    // MARK: - RX Sync Settings

    func queryRxAutoLock(device: SennheiserDevice, completion: @escaping (Result<Bool, Error>) -> Void) {
        queryBool(device: device, command: "RxLock", completion: completion)
    }

    func setRxAutoLock(device: SennheiserDevice, locked: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        setBool(device: device, command: "RxLock", value: locked, completion: completion)
    }

    func queryRxBalance(device: SennheiserDevice, completion: @escaping (Result<Int, Error>) -> Void) {
        queryInt(device: device, command: "Balance", completion: completion)
    }

    func setRxBalance(device: SennheiserDevice, value: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        setInt(device: device, command: "Balance", value: max(-15, min(15, value)), completion: completion)
    }

    func queryRxMode(device: SennheiserDevice, completion: @escaping (Result<SennheiserDevice.RxMode, Error>) -> Void) {
        queryInt(device: device, command: "RxMode") { result in
            completion(result.map { SennheiserDevice.RxMode(protocolValue: $0) })
        }
    }

    func setRxMode(device: SennheiserDevice, mode: SennheiserDevice.RxMode, completion: @escaping (Result<Void, Error>) -> Void) {
        setInt(device: device, command: "RxMode", value: mode.protocolValue, completion: completion)
    }

    func queryRxLimiter(device: SennheiserDevice, completion: @escaping (Result<Int, Error>) -> Void) {
        queryInt(device: device, command: "Limiter", completion: completion)
    }

    func setRxLimiter(device: SennheiserDevice, value: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        setInt(device: device, command: "Limiter", value: value, completion: completion)
    }

    func queryRxHighBoost(device: SennheiserDevice, completion: @escaping (Result<Bool, Error>) -> Void) {
        queryBool(device: device, command: "HiBoost", completion: completion)
    }

    func setRxHighBoost(device: SennheiserDevice, enabled: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        setBool(device: device, command: "HiBoost", value: enabled, completion: completion)
    }

    func queryRxSquelch(device: SennheiserDevice, completion: @escaping (Result<Int, Error>) -> Void) {
        queryInt(device: device, command: "Squelch", completion: completion)
    }

    func setRxSquelch(device: SennheiserDevice, value: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        setInt(device: device, command: "Squelch", value: max(5, min(25, value)), completion: completion)
    }

    // MARK: - Push / Connection

    func subscribePush(device: SennheiserDevice, timeout: Int = 60, rateMs: Int = 500) {
        sendCommand(device: device, command: "Push \(timeout) \(rateMs) 3") { _ in }
    }

    func disconnect(device: SennheiserDevice) {
        connections[device.id]?.cancel()
        connections.removeValue(forKey: device.id)
    }

    func disconnectAll() {
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
    }
}

enum ProtocolError: LocalizedError {
    case encodingFailed
    case noResponse
    case unexpectedResponse(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "Failed to encode command"
        case .noResponse: return "No response from device"
        case .unexpectedResponse(let r): return "Unexpected response: \(r)"
        case .parseError(let r): return "Could not parse response: \(r)"
        }
    }
}
