import SwiftUI

struct FrequencyAssignmentView: View {
    @EnvironmentObject var appState: AppState
    @State private var filterIEMOnly = true
    @State private var showActiveOnly = true
    @State private var selectedEntryID: String?

    private var filteredEntries: [WWBFrequencyEntry] {
        guard let showFile = appState.showFile else { return [] }
        var entries = showFile.entries
        if filterIEMOnly {
            let iemFiltered = entries.filter {
                let dt = $0.deviceType.lowercased()
                let series = $0.series.lowercased()
                let model = $0.model.lowercased()
                let mfr = $0.manufacturer.lowercased()
                return dt.contains("in ear") || dt.contains("iem") ||
                    model.contains("iem") || series.contains("iem") ||
                    series.contains("psm") ||
                    (mfr.contains("sennheiser") && series.contains("ew"))
            }
            entries = iemFiltered.isEmpty ? entries : iemFiltered
        }
        if showActiveOnly {
            entries = entries.filter { $0.isActive }
        }
        return entries.sorted { $0.frequencyKHz < $1.frequencyKHz }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            frequencyTable
        }
    }

    private var headerBar: some View {
        HStack {
            Text("Frequency Assignment")
                .font(.headline)

            Spacer()

            Toggle("IEM only", isOn: $filterIEMOnly)
                .toggleStyle(.checkbox)

            Toggle("Active only", isOn: $showActiveOnly)
                .toggleStyle(.checkbox)

            Divider()
                .frame(height: 16)

            Button("Send All") {
                appState.sendAllAssignments()
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.assignments.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var frequencyTable: some View {
        Table(filteredEntries, selection: $selectedEntryID) {
            TableColumn("Frequency") { entry in
                Text(entry.frequencyDisplayString)
                    .monospacedDigit()
                    .fontWeight(.medium)
            }
            .width(min: 100, ideal: 120)

            TableColumn("Name") { entry in
                Text(entry.name.isEmpty ? "—" : entry.name)
            }
            .width(min: 80, ideal: 120)

            TableColumn("Band") { entry in
                Text(entry.band)
                    .foregroundStyle(.secondary)
            }
            .width(min: 40, ideal: 60)

            TableColumn("Group/Ch") { entry in
                Text(entry.groupChannel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 80)

            TableColumn("Model") { entry in
                Text(entry.model)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 100)

            TableColumn("Level") { entry in
                Text(entry.scanLevelDisplayString)
                    .monospacedDigit()
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 80)

            TableColumn("Status") { entry in
                HStack(spacing: 4) {
                    Circle()
                        .fill(entry.isActive ? .green : .orange)
                        .frame(width: 6, height: 6)
                    Text(entry.isActive ? "Active" : "Backup")
                        .font(.caption)
                }
            }
            .width(min: 60, ideal: 70)

            TableColumn("Assign to") { entry in
                DevicePickerCell(
                    appState: appState,
                    entryID: entry.id,
                    frequencyKHz: entry.frequencyKHz
                )
            }
            .width(min: 140, ideal: 180)

            TableColumn("") { entry in
                if let deviceID = appState.assignments[entry.id],
                   let device = appState.devices.first(where: { $0.id == deviceID }) {
                    Button("Send") {
                        appState.sendFrequency(entry: entry, to: device)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .width(60)
        }
    }
}

struct DevicePickerCell: View {
    @ObservedObject var appState: AppState
    let entryID: String
    let frequencyKHz: Int

    var body: some View {
        Picker("", selection: binding) {
            Text("— not assigned —").tag("")
            ForEach(appState.devices) { device in
                Text("\(device.name) (\(device.host))")
                    .tag(device.id)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }

    private var binding: Binding<String> {
        Binding(
            get: { appState.assignments[entryID] ?? "" },
            set: { newValue in
                if newValue.isEmpty {
                    appState.assignments.removeValue(forKey: entryID)
                } else {
                    appState.assignments[entryID] = newValue
                }
            }
        )
    }
}
