import Foundation

struct SennheiserDevice: Identifiable, Hashable {
    let id: String
    var name: String
    var host: String
    var port: Int = 53212
    var isOnline: Bool = true

    // TX Settings
    var frequencyKHz: Int?
    var bank: Int?
    var channel: Int?
    var sensitivity: Int = 0
    var mode: AudioMode = .stereo
    var autoLock: Bool = false
    var rfMute: Bool = false
    var rfPower: Int = 10
    var warningAfPeak: Bool = true
    var warningRfMute: Bool = true

    // RX Sync Settings
    var rxAutoLock: Bool = false
    var rxBalance: Int = 0
    var rxMode: AudioMode = .stereo
    var rxLimiter: Bool = true
    var rxHighBoost: Bool = false
    var rxSquelch: Int = 5

    enum AudioMode: String, CaseIterable, Hashable {
        case mono = "Mono"
        case stereo = "Stereo"

        var protocolValue: Int {
            switch self {
            case .mono: return 0
            case .stereo: return 1
            }
        }

        init(protocolValue: Int) {
            self = protocolValue == 0 ? .mono : .stereo
        }
    }

    var frequencyMHz: Double? {
        guard let f = frequencyKHz else { return nil }
        return Double(f) / 1000.0
    }

    var frequencyDisplayString: String {
        guard let mhz = frequencyMHz else { return "—" }
        return String(format: "%.3f MHz", mhz)
    }

    static let rfPowerLevels = [10, 30, 50]
}
