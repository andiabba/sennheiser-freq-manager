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

    func queryFrequency(device: SennheiserDevice, completion: @escaping (Result<Int, Error>) -> Void) {
        sendCommand(device: device, command: "Frequency") { result in
            switch result {
            case .success(let response):
                let parts = response.split(separator: " ")
                if parts.count >= 2, let freq = Int(parts[1]) {
                    completion(.success(freq))
                } else {
                    completion(.failure(ProtocolError.parseError(response)))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func queryName(device: SennheiserDevice, completion: @escaping (Result<String, Error>) -> Void) {
        sendCommand(device: device, command: "Name") { result in
            switch result {
            case .success(let response):
                if response.hasPrefix("Name ") {
                    let name = String(response.dropFirst(5))
                    completion(.success(name))
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

    func setMute(device: SennheiserDevice, muted: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        sendCommand(device: device, command: "Mute \(muted ? 1 : 0)") { result in
            completion(result.map { _ in () })
        }
    }

    func setSensitivity(device: SennheiserDevice, dB: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        let clamped = max(-42, min(0, dB))
        sendCommand(device: device, command: "Sensitivity \(clamped)") { result in
            completion(result.map { _ in () })
        }
    }

    func setMode(device: SennheiserDevice, mode: SennheiserDevice.AudioMode, completion: @escaping (Result<Void, Error>) -> Void) {
        sendCommand(device: device, command: "Mode \(mode.protocolValue)") { result in
            completion(result.map { _ in () })
        }
    }

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
