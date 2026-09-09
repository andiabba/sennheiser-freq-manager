import Foundation

struct WWBParser {
    enum ParseError: LocalizedError {
        case fileNotReadable
        case invalidXML(String)
        case noCoordinationData

        var errorDescription: String? {
            switch self {
            case .fileNotReadable: return "Could not read file"
            case .invalidXML(let detail): return "Invalid XML: \(detail)"
            case .noCoordinationData: return "No coordination data found in file"
            }
        }
    }

    static func parse(fileURL: URL) throws -> WWBShowFile {
        guard let data = try? Data(contentsOf: fileURL) else {
            throw ParseError.fileNotReadable
        }

        let parser = WWBXMLParser(data: data)
        guard parser.parse() else {
            throw ParseError.invalidXML(parser.errorMessage ?? "Unknown error")
        }

        if parser.entries.isEmpty {
            throw ParseError.noCoordinationData
        }

        let scanData = loadScanData(scanPath: parser.scanFilePath, showFileURL: fileURL)
        var entries = parser.entries
        if !scanData.isEmpty {
            for i in entries.indices {
                entries[i].scanLevelDBm = lookupLevel(frequencyMHz: entries[i].frequencyMHz, scanData: scanData)
            }
        }

        return WWBShowFile(
            fileName: fileURL.lastPathComponent,
            date: parser.showDate,
            version: parser.showVersion,
            entries: entries,
            scanDataPath: parser.scanFilePath
        )
    }

    private static func loadScanData(scanPath: String?, showFileURL: URL) -> [(freqMHz: Double, levelDBm: Double)] {
        guard let path = scanPath, !path.isEmpty else { return [] }

        let candidates = [
            path,
            (showFileURL.deletingLastPathComponent().path as NSString).appendingPathComponent((path as NSString).lastPathComponent),
            NSString(string: "~/rfexplorer-detailed-scan-master____/\((path as NSString).lastPathComponent)").expandingTildeInPath,
            NSString(string: "~/rfexplorer-detailed-scan-master/\((path as NSString).lastPathComponent)").expandingTildeInPath,
        ]

        for candidate in candidates {
            let url = URL(fileURLWithPath: candidate)
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                return parseScanCSV(content)
            }
        }
        return []
    }

    private static func parseScanCSV(_ content: String) -> [(freqMHz: Double, levelDBm: Double)] {
        var data: [(freqMHz: Double, levelDBm: Double)] = []
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let parts = trimmed.components(separatedBy: ",")
            guard parts.count >= 2,
                  let freq = Double(parts[0]),
                  let level = Double(parts[1]) else { continue }
            data.append((freqMHz: freq, levelDBm: level))
        }
        data.sort { $0.freqMHz < $1.freqMHz }
        return data
    }

    private static func lookupLevel(frequencyMHz: Double, scanData: [(freqMHz: Double, levelDBm: Double)]) -> Double? {
        guard !scanData.isEmpty else { return nil }

        var lo = 0, hi = scanData.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if scanData[mid].freqMHz < frequencyMHz { lo = mid + 1 } else { hi = mid }
        }

        if lo == 0 {
            return abs(scanData[0].freqMHz - frequencyMHz) < 0.1 ? scanData[0].levelDBm : nil
        }
        if lo >= scanData.count {
            return abs(scanData.last!.freqMHz - frequencyMHz) < 0.1 ? scanData.last!.levelDBm : nil
        }

        let before = scanData[lo - 1]
        let after = scanData[lo]

        if abs(after.freqMHz - frequencyMHz) < 0.001 { return after.levelDBm }
        if abs(before.freqMHz - frequencyMHz) < 0.001 { return before.levelDBm }

        if (after.freqMHz - before.freqMHz) < 0.001 { return before.levelDBm }

        let t = (frequencyMHz - before.freqMHz) / (after.freqMHz - before.freqMHz)
        if t < 0 || t > 1 { return nil }
        return before.levelDBm + t * (after.levelDBm - before.levelDBm)
    }

    static func parseCSV(fileURL: URL) throws -> [WWBFrequencyEntry] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            throw ParseError.fileNotReadable
        }

        var entries: [WWBFrequencyEntry] = []
        let lines = content.components(separatedBy: .newlines)

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let parts = trimmed.components(separatedBy: CharacterSet(charactersIn: ",;\t"))
            guard parts.count >= 1 else { continue }

            if let freqMHz = Double(parts[0].trimmingCharacters(in: .whitespaces)) {
                let freqKHz = Int(freqMHz * 1000)
                let name = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : "Ch \(index + 1)"

                entries.append(WWBFrequencyEntry(
                    id: UUID().uuidString,
                    frequencyKHz: freqKHz,
                    name: name,
                    zone: "Default",
                    band: "",
                    series: "",
                    manufacturer: "",
                    model: "",
                    deviceType: "In Ear Monitor",
                    groupChannel: "",
                    isActive: true,
                    isBackup: false,
                    color: "#585858",
                    scanLevelDBm: nil
                ))
            }
        }

        return entries
    }
}

private class WWBXMLParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var currentElement = ""
    private var elementStack: [String] = []
    private var currentText = ""
    private var currentEntry: [String: String] = [:]
    private var inFreqEntry = false
    private var inCompatKey = false
    private var inDevCategory = false
    private var inScanData = false
    private var inInventoryDevice = false
    private var currentInventoryDevice: [String: String] = [:]
    private var inventoryDevices: [String: [String: String]] = [:]

    var entries: [WWBFrequencyEntry] = []
    var showDate = ""
    var showVersion = ""
    var scanFilePath: String?
    var errorMessage: String?

    init(data: Data) {
        self.parser = XMLParser(data: data)
        super.init()
        self.parser.delegate = self
    }

    func parse() -> Bool {
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentElement = elementName
        elementStack.append(elementName)
        currentText = ""

        if elementName == "show" {
            showDate = attributes["date"] ?? ""
            showVersion = attributes["appl_version"] ?? ""
        }

        if elementName == "scan_data" {
            inScanData = true
        }

        if elementName == "device" && !inFreqEntry {
            inInventoryDevice = true
            currentInventoryDevice = [:]
        }

        if elementName == "freq_entry" {
            inFreqEntry = true
            currentEntry = [:]
            currentEntry["id"] = attributes["id"] ?? UUID().uuidString
            currentEntry["color"] = attributes["color"] ?? "#585858"
            currentEntry["tag"] = attributes["tag"] ?? ""
        }

        if inFreqEntry && elementName == "compat_key" {
            inCompatKey = true
        }

        if inFreqEntry && elementName == "dev_category" {
            inDevCategory = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if inScanData && elementName == "file_path" {
            scanFilePath = text
        }
        if elementName == "scan_data" { inScanData = false }

        if inFreqEntry {
            if inCompatKey {
                switch elementName {
                case "zone": currentEntry["zone"] = text
                case "series": currentEntry["series"] = text
                case "band": currentEntry["band"] = text
                default: break
                }
            }

            if inDevCategory {
                if elementName == "dev_type" && text != "Unknown" {
                    if currentEntry["dev_type"] == nil || currentEntry["dev_type"] == "Unknown" {
                        currentEntry["dev_type"] = text
                    }
                }
            }

            switch elementName {
            case "value": currentEntry["value"] = text
            case "gr_ch": currentEntry["gr_ch"] = text
            case "context_role": currentEntry["context_role"] = text
            case "model": currentEntry["model"] = text
            case "manufacturer": currentEntry["manufacturer"] = text
            case "source_name": currentEntry["source_name"] = text
            case "source_id": currentEntry["source_id"] = text
            default: break
            }
        }

        if inInventoryDevice && !inFreqEntry {
            switch elementName {
            case "id": currentInventoryDevice["id"] = text
            case "device_name": currentInventoryDevice["device_name"] = text
            case "channel_name": currentInventoryDevice["channel_name"] = text
            case "series": currentInventoryDevice["series"] = text
            case "model": currentInventoryDevice["model"] = text
            default: break
            }
        }

        if elementName == "device" && inInventoryDevice && !inFreqEntry {
            inInventoryDevice = false
            if let id = currentInventoryDevice["id"] {
                inventoryDevices[id] = currentInventoryDevice
            }
        }

        if elementName == "compat_key" { inCompatKey = false }
        if elementName == "dev_category" { inDevCategory = false }

        if elementName == "freq_entry" {
            inFreqEntry = false

            let contextRole = Int(currentEntry["context_role"] ?? "7") ?? 7
            let freqKHz = Int(currentEntry["value"] ?? "0") ?? 0

            if freqKHz > 0 {
                let entryID = currentEntry["id"] ?? UUID().uuidString
                let sourceID = currentEntry["source_id"] ?? entryID
                let inventoryInfo = inventoryDevices[sourceID] ?? inventoryDevices[entryID]

                var name = currentEntry["source_name"] ?? ""
                if name.isEmpty { name = currentEntry["tag"] ?? "" }
                if name.isEmpty { name = inventoryInfo?["channel_name"] ?? "" }
                if name.isEmpty { name = inventoryInfo?["device_name"] ?? "" }

                var devType = currentEntry["dev_type"] ?? ""
                if devType.isEmpty || devType == "Unknown" {
                    let series = (currentEntry["series"] ?? "").lowercased()
                    if series.contains("iem") || series.contains("psm") {
                        devType = "In Ear Monitor"
                    }
                }

                let entry = WWBFrequencyEntry(
                    id: entryID,
                    frequencyKHz: freqKHz,
                    name: name,
                    zone: currentEntry["zone"] ?? "Default",
                    band: currentEntry["band"] ?? "",
                    series: currentEntry["series"] ?? "",
                    manufacturer: currentEntry["manufacturer"] ?? "",
                    model: currentEntry["model"] ?? "",
                    deviceType: devType,
                    groupChannel: currentEntry["gr_ch"] ?? "",
                    isActive: contextRole == 7,
                    isBackup: contextRole == 9,
                    color: currentEntry["color"] ?? "#585858",
                    scanLevelDBm: nil
                )
                entries.append(entry)
            }
        }

        if !elementStack.isEmpty { elementStack.removeLast() }
        currentText = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        errorMessage = parseError.localizedDescription
    }
}
