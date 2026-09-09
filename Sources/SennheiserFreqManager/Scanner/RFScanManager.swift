import Foundation
import Combine

class RFScanManager: ObservableObject {
    @Published var isScanning = false
    @Published var progress: Double = 0
    @Published var statusMessage = ""
    @Published var lastScanPath: String?
    @Published var errorMessage: String?

    private var currentProcess: Process?
    private var cancelled = false

    var scriptPath: String
    var outputDirectory: String

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        scriptPath = "\(home)/rfexplorer-detailed-scan/venv/bin/rfexplorerDetailedScan"
        outputDirectory = "\(home)/rfexplorer-detailed-scan"
    }

    var scriptAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: scriptPath)
    }

    func scan(
        ranges: [FrequencyBand.ScanRange],
        stepResolution: Int = 2,
        iterations: Int = 10,
        aggregation: String = "average",
        serialPort: String? = nil
    ) {
        guard !ranges.isEmpty else {
            errorMessage = "Kein Frequenzbereich ausgewählt"
            return
        }
        guard scriptAvailable else {
            errorMessage = "RF Explorer Script nicht gefunden: \(scriptPath)"
            return
        }

        isScanning = true
        progress = 0
        errorMessage = nil
        cancelled = false

        let ts = DateFormatter()
        ts.dateFormat = "yyyy-MM-dd-HHmmss"
        let filename = "scan-\(ts.string(from: Date())).csv"
        let outputPath = (outputDirectory as NSString).appendingPathComponent(filename)

        let totalChunks = FrequencyBand.totalChunks(ranges: ranges, stepResolution: stepResolution)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.performScan(
                ranges: ranges,
                outputPath: outputPath,
                stepResolution: stepResolution,
                iterations: iterations,
                aggregation: aggregation,
                serialPort: serialPort,
                totalChunks: totalChunks
            )
        }
    }

    func cancelScan() {
        cancelled = true
        currentProcess?.terminate()
        currentProcess = nil
        DispatchQueue.main.async { [weak self] in
            self?.isScanning = false
            self?.statusMessage = "Scan abgebrochen"
        }
    }

    // MARK: - Private

    private func performScan(
        ranges: [FrequencyBand.ScanRange],
        outputPath: String,
        stepResolution: Int,
        iterations: Int,
        aggregation: String,
        serialPort: String?,
        totalChunks: Int
    ) {
        var allData: [(freq: Double, level: Double)] = []
        var completedChunks = 0

        for (idx, range) in ranges.enumerated() {
            if cancelled { return }

            if idx > 0 {
                Thread.sleep(forTimeInterval: 2)
            }

            updateMain { [weak self] in
                self?.statusMessage = "Scanne \(range.startMHz)–\(range.endMHz) MHz…"
            }

            let tempPath = NSTemporaryDirectory() + "rfscan_\(idx)_\(UUID().uuidString).csv"

            var args = [
                tempPath,
                "-s", "\(range.startMHz)",
                "-e", "\(range.endMHz)",
                "-r", "\(stepResolution)",
                "-i", "\(iterations)",
                "-a", aggregation,
                "-v"
            ]
            if let port = serialPort, !port.isEmpty {
                args += ["-p", port]
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: scriptPath)
            process.arguments = args

            let stderrPipe = Pipe()
            process.standardError = stderrPipe
            process.standardOutput = FileHandle.nullDevice

            var stderrBuffer = ""
            let bufferLock = NSLock()

            stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }

                bufferLock.lock()
                stderrBuffer += chunk
                while let nlRange = stderrBuffer.range(of: "\n") {
                    let line = String(stderrBuffer[stderrBuffer.startIndex..<nlRange.lowerBound])
                    stderrBuffer = String(stderrBuffer[nlRange.upperBound...])

                    if line.contains("starting process for") || line.contains("Updating freq range") {
                        completedChunks += 1
                        let pct = min(Double(completedChunks) / Double(max(totalChunks, 1)), 0.99)
                        self?.updateMain {
                            self?.progress = pct
                            self?.statusMessage = "Chunk \(completedChunks)/\(totalChunks) (\(range.startMHz)–\(range.endMHz) MHz)"
                        }
                    }
                }
                bufferLock.unlock()
            }

            currentProcess = process

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                updateMain { [weak self] in
                    self?.errorMessage = "Fehler beim Starten: \(error.localizedDescription)"
                    self?.isScanning = false
                }
                return
            }

            stderrPipe.fileHandleForReading.readabilityHandler = nil

            if cancelled { return }

            if process.terminationStatus != 0 {
                updateMain { [weak self] in
                    self?.errorMessage = "Scan fehlgeschlagen (Exit Code \(process.terminationStatus))"
                    self?.isScanning = false
                }
                return
            }

            if let contents = try? String(contentsOfFile: tempPath, encoding: .utf8) {
                for line in contents.split(separator: "\n") where !line.isEmpty {
                    let parts = line.split(separator: ",")
                    if parts.count == 2,
                       let freq = Double(parts[0]),
                       let level = Double(parts[1]) {
                        allData.append((freq, level))
                    }
                }
            }
            try? FileManager.default.removeItem(atPath: tempPath)
        }

        allData.sort { $0.freq < $1.freq }
        let csvContent = allData.map { "\($0.freq),\($0.level)" }.joined(separator: "\n") + "\n"

        do {
            try csvContent.write(toFile: outputPath, atomically: true, encoding: .utf8)
            updateMain { [weak self] in
                self?.lastScanPath = outputPath
                self?.statusMessage = "Scan fertig: \(allData.count) Messpunkte → \((outputPath as NSString).lastPathComponent)"
                self?.progress = 1.0
                self?.isScanning = false
            }
        } catch {
            updateMain { [weak self] in
                self?.errorMessage = "CSV speichern fehlgeschlagen: \(error.localizedDescription)"
                self?.isScanning = false
            }
        }
    }

    private func updateMain(_ block: @escaping () -> Void) {
        DispatchQueue.main.async(execute: block)
    }

    // MARK: - Serial port detection

    static func availableSerialPorts() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: "/dev") else { return [] }
        return files
            .filter { $0.hasPrefix("tty.usb") || $0.hasPrefix("cu.usb") || $0.hasPrefix("cu.SLAB") || $0.hasPrefix("tty.SLAB") }
            .map { "/dev/\($0)" }
            .sorted()
    }
}
