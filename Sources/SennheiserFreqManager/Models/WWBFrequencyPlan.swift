import Foundation

struct WWBFrequencyEntry: Identifiable, Hashable {
    let id: String
    var frequencyKHz: Int
    var name: String
    var zone: String
    var band: String
    var series: String
    var manufacturer: String
    var model: String
    var deviceType: String
    var groupChannel: String
    var isActive: Bool
    var isBackup: Bool
    var color: String
    var txPowerMW: Int?

    var frequencyMHz: Double {
        Double(frequencyKHz) / 1000.0
    }

    var frequencyDisplayString: String {
        String(format: "%.3f MHz", frequencyMHz)
    }

    var txPowerDBm: Double? {
        guard let mw = txPowerMW, mw > 0 else { return nil }
        return 10.0 * log10(Double(mw))
    }

    var txPowerDisplayString: String {
        guard let dbm = txPowerDBm else { return "—" }
        return String(format: "%.0f dBm", dbm)
    }
}

struct WWBShowFile {
    var fileName: String
    var date: String
    var version: String
    var entries: [WWBFrequencyEntry]

    var activeEntries: [WWBFrequencyEntry] {
        entries.filter { $0.isActive }
    }

    var backupEntries: [WWBFrequencyEntry] {
        entries.filter { $0.isBackup }
    }

    var iemEntries: [WWBFrequencyEntry] {
        entries.filter { $0.deviceType.lowercased().contains("in ear") || $0.deviceType.lowercased().contains("iem") }
    }
}
