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
    // Device returns "Frequency <kHz> <bank> <channel>" as combined response

    struct FrequencyInfo {
        let frequencyKHz: Int
        let bank: Int
        let channel: Int
    }

    func queryFrequencyInfo(device: SennheiserDevice, completion: @escaping (Result<FrequencyInfo, Error>) -> Void) {
        sendCommand(device: device, command: "Frequency") { result in
            switch result {
            case .success(let response):
                let parts = response.split(separator: " ")
                if parts.count >= 4,
                   parts[0] == "Frequency",
                   let freq = Int(parts[1]),
                   let bank = Int(parts[2]),
                   let ch = Int(parts[3]) {
                    completion(.success(FrequencyInfo(frequencyKHz: freq, bank: bank, channel: ch)))
                } else if parts.count >= 2, parts[0] == "Frequency", let freq = Int(parts[1]) {
                    completion(.success(FrequencyInfo(frequencyKHz: freq, bank: 0, channel: 0)))
                } else {
                    completion(.failure(ProtocolError.parseError(response)))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func queryFrequency(device: SennheiserDevice, completion: @escaping (Result<Int, Error>) -> Void) {
        queryFrequencyInfo(device: device) { result in
            completion(result.map { $0.frequencyKHz })
        }
    }

    func queryBank(device: SennheiserDevice, completion: @escaping (Result<Int, Error>) -> Void) {
        queryFrequencyInfo(device: device) { result in
            completion(result.map { $0.bank })
        }
    }

    func queryChannel(device: SennheiserDevice, completion: @escaping (Result<Int, Error>) -> Void) {
        queryFrequencyInfo(device: device) { result in
            completion(result.map { $0.channel })
        }
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

    func setBank(device: SennheiserDevice, bank: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.failure(ProtocolError.unexpectedResponse("Bank is set via Frequency command")))
    }

    func setChannel(device: SennheiserDevice, channel: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.failure(ProtocolError.unexpectedResponse("Channel is set via Frequency command")))
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

    func queryMute(device: SennheiserDevice, completion: @escaping (Result<Bool, Error>) -> Void) {
        queryBool(device: device, command: "Mute", completion: completion)
    }

    func setMute(device: SennheiserDevice, muted: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        setBool(device: device, command: "Mute", value: muted, completion: completion)
    }

    // MARK: - Equalizer (6-band)

    func queryEqualizer(device: SennheiserDevice, completion: @escaping (Result<[Int], Error>) -> Void) {
        sendCommand(device: device, command: "Equalizer") { result in
            switch result {
            case .success(let response):
                let parts = response.split(separator: " ")
                if parts.count >= 7, parts[0] == "Equalizer" {
                    let values = parts.dropFirst().compactMap { Int($0) }
                    if values.count == 6 {
                        completion(.success(values))
                        return
                    }
                }
                completion(.failure(ProtocolError.parseError(response)))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func setEqualizer(device: SennheiserDevice, values: [Int], completion: @escaping (Result<Void, Error>) -> Void) {
        let valStr = values.map { String($0) }.joined(separator: " ")
        sendCommand(device: device, command: "Equalizer \(valStr)") { result in
            completion(result.map { _ in () })
        }
    }

    // MARK: - Push / Connection

    func subscribePush(device: SennheiserDevice, timeout: Int = 60, rateMs: Int = 500) {
        sendCommand(device: device, command: "Push \(timeout) \(rateMs) 1") { _ in }
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
