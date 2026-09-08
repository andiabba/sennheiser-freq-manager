import Foundation

struct SennheiserDevice: Identifiable, Hashable {
    let id: String
    var name: String
    var host: String
    var port: Int = 53212
    var frequencyKHz: Int?
    var muted: Bool = false
    var mode: AudioMode = .stereo
    var sensitivity: Int = 0
    var isOnline: Bool = true

    enum AudioMode: String, CaseIterable {
        case mono = "Mono"
        case stereo = "Stereo"

        var protocolValue: Int {
            switch self {
            case .mono: return 0
            case .stereo: return 1
            }
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
}

struct DeviceStatus {
    var rfMute: Bool = false
    var afPeak1: Int = 0
    var afPeak2: Int = 0
    var afHold1: Int = 0
    var afHold2: Int = 0
}
