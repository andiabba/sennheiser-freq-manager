import SwiftUI

struct RFScanView: View {
    @ObservedObject var scanManager: RFScanManager

    @State private var selectedBandIDs: Set<String> = []
    @State private var useCustomRange = false
    @State private var customStartMHz = ""
    @State private var customEndMHz = ""
    @State private var stepResolution = 2
    @State private var iterations = 10
    @State private var aggregation = "average"
    @State private var serialPort = ""
    @State private var scanName = "scan"

    private var mergedRanges: [FrequencyBand.ScanRange] {
        var bands = FrequencyBand.allBands.filter { selectedBandIDs.contains($0.id) }
        if useCustomRange,
           let s = Int(customStartMHz), let e = Int(customEndMHz), s < e {
            bands.append(FrequencyBand(id: "custom", manufacturer: "Custom", name: "Custom", startMHz: s, endMHz: e))
        }
        return FrequencyBand.mergeRanges(bands)
    }

    private var totalBandwidth: Int {
        mergedRanges.reduce(0) { $0 + $1.bandwidthMHz }
    }

    private var estimatedChunks: Int {
        FrequencyBand.totalChunks(ranges: mergedRanges, stepResolution: stepResolution)
    }

    private var previewFilename: String {
        let ts = DateFormatter()
        ts.dateFormat = "yyyy-MM-dd-HHmmss"
        let base = scanName.trimmingCharacters(in: .whitespaces)
        let name = base.isEmpty ? "scan" : base
        return "\(name)-\(ts.string(from: Date())).csv"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                bandSelection
                customRange
                if !mergedRanges.isEmpty { scanSummary }
                outputSection
                parameters
                serialPortSection
                scanControls
                if let path = scanManager.lastScanPath { resultSection(path) }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "wave.3.right")
                .font(.title2)
            Text("RF Explorer Scan")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            if !scanManager.scriptAvailable {
                Label("Script nicht gefunden", systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
            }
        }
    }

    // MARK: - Band selection

    private var bandSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Frequenzbänder")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 20) {
                    ForEach(FrequencyBand.bandGroups, id: \.title) { group in
                        bandGroup(group.title, bands: group.bands)
                        if group.title != FrequencyBand.bandGroups.last?.title {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func bandGroup(_ title: String, bands: [FrequencyBand]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Button(selectedBandIDs.isSuperset(of: Set(bands.map(\.id))) ? "Keine" : "Alle") {
                    let ids = Set(bands.map(\.id))
                    if selectedBandIDs.isSuperset(of: ids) {
                        selectedBandIDs.subtract(ids)
                    } else {
                        selectedBandIDs.formUnion(ids)
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(.bottom, 2)

            ForEach(bands) { band in
                Toggle(isOn: Binding(
                    get: { selectedBandIDs.contains(band.id) },
                    set: { on in
                        if on { selectedBandIDs.insert(band.id) }
                        else { selectedBandIDs.remove(band.id) }
                    }
                )) {
                    HStack {
                        Text(band.name)
                            .fontWeight(.medium)
                            .frame(width: 40, alignment: .leading)
                        Text(band.rangeString)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
        .frame(minWidth: 190, alignment: .leading)
    }

    // MARK: - Custom range

    private var customRange: some View {
        HStack {
            Toggle("Custom Range", isOn: $useCustomRange)
                .toggleStyle(.checkbox)
            if useCustomRange {
                TextField("Start", text: $customStartMHz)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                Text("–")
                TextField("End", text: $customEndMHz)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                Text("MHz")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Scan summary

    private var scanSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Scan-Bereiche (zusammengeführt)")
                .font(.subheadline)
                .fontWeight(.medium)
            ForEach(mergedRanges, id: \.self) { range in
                HStack {
                    Text("\(range.startMHz)–\(range.endMHz) MHz")
                        .monospacedDigit()
                    Text("(\(range.bandwidthMHz) MHz)")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            Text("Gesamt: \(totalBandwidth) MHz, ~\(estimatedChunks) Chunks")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08))
        .cornerRadius(6)
    }

    // MARK: - Output

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ausgabe")
                .font(.headline)

            HStack {
                Text("Dateiname:")
                    .foregroundStyle(.secondary)
                TextField("scan", text: $scanName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                Text("-\(datePreview()).csv")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Text("Ordner:")
                    .foregroundStyle(.secondary)
                Text(scanManager.outputDirectory)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Ändern…") {
                    chooseOutputDirectory()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Text("Vorschau: \(previewFilename)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Parameters

    private var parameters: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scan-Parameter")
                .font(.headline)

            HStack(spacing: 20) {
                HStack {
                    Text("Resolution:")
                        .foregroundStyle(.secondary)
                    Picker("", selection: $stepResolution) {
                        Text("1 MHz").tag(1)
                        Text("2 MHz").tag(2)
                        Text("4 MHz").tag(4)
                        Text("5 MHz").tag(5)
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 100)
                    .labelsHidden()
                }

                HStack {
                    Text("Iterations:")
                        .foregroundStyle(.secondary)
                    Picker("", selection: $iterations) {
                        Text("5").tag(5)
                        Text("10").tag(10)
                        Text("15").tag(15)
                        Text("20").tag(20)
                        Text("30").tag(30)
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 80)
                    .labelsHidden()
                }

                HStack {
                    Text("Aggregation:")
                        .foregroundStyle(.secondary)
                    Picker("", selection: $aggregation) {
                        Text("Average").tag("average")
                        Text("Max Hold").tag("max")
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 180)
                    .labelsHidden()
                }
            }
        }
    }

    // MARK: - Serial port

    private var serialPortSection: some View {
        HStack {
            Text("Serial Port:")
                .foregroundStyle(.secondary)
            Picker("", selection: $serialPort) {
                Text("Auto-detect").tag("")
                ForEach(RFScanManager.availableSerialPorts(), id: \.self) { port in
                    Text(port).tag(port)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 300)
            .labelsHidden()

            Button(action: { _ = RFScanManager.availableSerialPorts() }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Scan controls

    private var scanControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if scanManager.isScanning {
                    Button("Scan abbrechen") {
                        scanManager.cancelScan()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                } else {
                    Button("Scan starten") {
                        let name = scanName.trimmingCharacters(in: .whitespaces)
                        scanManager.scan(
                            ranges: mergedRanges,
                            stepResolution: stepResolution,
                            iterations: iterations,
                            aggregation: aggregation,
                            serialPort: serialPort.isEmpty ? nil : serialPort,
                            filePrefix: name.isEmpty ? "scan" : name
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(mergedRanges.isEmpty || !scanManager.scriptAvailable)
                }
            }

            if scanManager.isScanning {
                ProgressView(value: scanManager.progress)
                    .progressViewStyle(.linear)
            }

            if !scanManager.statusMessage.isEmpty {
                Text(scanManager.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = scanManager.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    // MARK: - Results

    private func resultSection(_ path: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("Letzter Scan")
                .font(.headline)
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.accentColor)
                Text((path as NSString).lastPathComponent)
                    .font(.caption)
                    .monospacedDigit()
                Spacer()
                Button("Im Finder zeigen") {
                    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Pfad kopieren") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(path, forType: .string)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Helpers

    private func datePreview() -> String {
        let ts = DateFormatter()
        ts.dateFormat = "yyyy-MM-dd-HHmmss"
        return ts.string(from: Date())
    }

    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Ausgabeordner für Scan-CSV wählen"
        if panel.runModal() == .OK, let url = panel.url {
            scanManager.outputDirectory = url.path
        }
    }
}
