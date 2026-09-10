import Foundation

struct SennheiserDevice: Identifiable, Hashable {
    let id: String
    var name: String
    var host: String
    var port: Int = 53213
    var isOnline: Bool = true

    // TX Settings
    var frequencyKHz: Int?
    var bank: Int?
    var channel: Int?
    var sensitivity: Int = 0       // 0 to -42, step 3
    var mode: TxMode = .stereo
    var autoLock: Bool = false
    var rfMute: Bool = false
    var rfPower: Int = 30          // 10, 30, 50 mW
    var warningAfPeak: Bool = true
    var warningRfMute: Bool = true

    // RX Sync Settings (value + sync enable flag per parameter)
    var rxAutoLock: Bool = false
    var rxAutoLockSync: Bool = true
    var rxBalance: Int = 0         // -15 (L15) to +15 (R15), 0 = L=R
    var rxBalanceSync: Bool = true
    var rxMode: RxMode = .stereo
    var rxModeSync: Bool = true
    var rxLimiter: Int = -18       // -18, -12, -6, or 0 = off
    var rxLimiterSync: Bool = true
    var rxHighBoost: Bool = false
    var rxHighBoostSync: Bool = true
    var rxSquelch: Int = 5         // 5 to 25, step 2
    var rxSquelchSync: Bool = true

    enum TxMode: String, CaseIterable, Hashable {
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

    enum RxMode: String, CaseIterable, Hashable {
        case stereo = "Stereo"
        case focus = "Focus"

        var protocolValue: Int {
            switch self {
            case .stereo: return 0
            case .focus: return 1
            }
        }

        init(protocolValue: Int) {
            self = protocolValue == 0 ? .stereo : .focus
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
    static let sensitivityValues = stride(from: 0, through: -42, by: -3).map { $0 }
    static let squelchValues = stride(from: 5, through: 25, by: 2).map { $0 }
    static let limiterValues = [0, -6, -12, -18]   // 0 = off
    static let bankRange = 1...26  // 1-20 preset + U1-U6 (21-26)
    static let channelRange = 1...16

    var balanceDisplayString: String {
        if rxBalance == 0 { return "L = R" }
        if rxBalance < 0 { return "L\(abs(rxBalance))" }
        return "R\(rxBalance)"
    }

    var limiterDisplayString: String {
        if rxLimiter == 0 { return "Off" }
        return "\(rxLimiter) dB"
    }

    var bankDisplayString: String {
        guard let b = bank else { return "—" }
        if b <= 20 { return "\(b)" }
        return "U\(b - 20)"
    }
}
