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

        return WWBShowFile(
            fileName: fileURL.lastPathComponent,
            date: parser.showDate,
            version: parser.showVersion,
            entries: parser.entries
        )
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
                    color: "#585858"
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

    var entries: [WWBFrequencyEntry] = []
    var showDate = ""
    var showVersion = ""
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
                if elementName == "dev_type" {
                    currentEntry["dev_type"] = text
                }
            }

            switch elementName {
            case "value": currentEntry["value"] = text
            case "gr_ch": currentEntry["gr_ch"] = text
            case "context_role": currentEntry["context_role"] = text
            case "model": currentEntry["model"] = text
            case "manufacturer": currentEntry["manufacturer"] = text
            case "source_name": currentEntry["source_name"] = text
            default: break
            }
        }

        if elementName == "compat_key" { inCompatKey = false }
        if elementName == "dev_category" { inDevCategory = false }

        if elementName == "freq_entry" {
            inFreqEntry = false

            let contextRole = Int(currentEntry["context_role"] ?? "7") ?? 7
            let freqKHz = Int(currentEntry["value"] ?? "0") ?? 0

            if freqKHz > 0 {
                let entry = WWBFrequencyEntry(
                    id: currentEntry["id"] ?? UUID().uuidString,
                    frequencyKHz: freqKHz,
                    name: currentEntry["source_name"] ?? currentEntry["tag"] ?? "",
                    zone: currentEntry["zone"] ?? "Default",
                    band: currentEntry["band"] ?? "",
                    series: currentEntry["series"] ?? "",
                    manufacturer: currentEntry["manufacturer"] ?? "",
                    model: currentEntry["model"] ?? "",
                    deviceType: currentEntry["dev_type"] ?? "",
                    groupChannel: currentEntry["gr_ch"] ?? "",
                    isActive: contextRole == 7,
                    isBackup: contextRole == 9,
                    color: currentEntry["color"] ?? "#585858"
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
