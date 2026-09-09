import SwiftUI

struct DeviceDetailView: View {
    @ObservedObject var appState: AppState
    let deviceID: String

    @State private var editingName = ""
    @State private var editingFrequency = ""
    @State private var isEditingName = false
    @State private var isEditingFrequency = false

    private var device: SennheiserDevice? {
        appState.devices.first { $0.id == deviceID }
    }

    var body: some View {
        if let device = device {
            ScrollView {
                VStack(spacing: 0) {
                    deviceHeader(device)
                    Divider()
                    settingsSection(device)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(nsColor: .windowBackgroundColor))
            .onAppear {
                appState.queryDeviceState(device)
            }
        } else {
            Text("Device not found")
                .foregroundStyle(.secondary)
        }
    }

    private func deviceHeader(_ device: SennheiserDevice) -> some View {
        VStack(spacing: 8) {
            HStack {
                Circle()
                    .fill(device.isOnline ? .green : .red)
                    .frame(width: 10, height: 10)
                Text(device.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Refresh") {
                    appState.queryDeviceState(device)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            HStack {
                Text(device.host)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Port \(device.port)")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(device.frequencyDisplayString)
                    .font(.title3)
                    .monospacedDigit()
                    .fontWeight(.medium)
            }
        }
        .padding()
    }

    private func settingsSection(_ device: SennheiserDevice) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.headline)
                .padding(.top, 4)

            // Name
            settingRow("Name") {
                if isEditingName {
                    HStack {
                        TextField("Device Name", text: $editingName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 200)
                            .onSubmit { submitName(device) }
                        Button("Set") { submitName(device) }
                            .buttonStyle(.bordered)
                        Button("Cancel") { isEditingName = false }
                            .buttonStyle(.bordered)
                    }
                } else {
                    HStack {
                        Text(device.name)
                        Spacer()
                        Button("Edit") {
                            editingName = device.name
                            isEditingName = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            Divider()

            // Frequency
            settingRow("Frequency") {
                if isEditingFrequency {
                    HStack {
                        TextField("MHz", text: $editingFrequency)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .onSubmit { submitFrequency(device) }
                        Text("MHz")
                            .foregroundStyle(.secondary)
                        Button("Set") { submitFrequency(device) }
                            .buttonStyle(.bordered)
                        Button("Cancel") { isEditingFrequency = false }
                            .buttonStyle(.bordered)
                    }
                } else {
                    HStack {
                        Text(device.frequencyDisplayString)
                            .monospacedDigit()
                        Spacer()
                        Button("Edit") {
                            if let mhz = device.frequencyMHz {
                                editingFrequency = String(format: "%.3f", mhz)
                            }
                            isEditingFrequency = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            Divider()

            // Mute
            settingRow("Mute") {
                Toggle(device.muted ? "Muted" : "Active", isOn: muteBinding(device))
                    .toggleStyle(.switch)
            }

            Divider()

            // Sensitivity
            settingRow("Sensitivity") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(device.sensitivity) dB")
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                        Slider(
                            value: sensitivityBinding(device),
                            in: -42...0,
                            step: 3
                        )
                        .frame(maxWidth: 250)
                    }
                    Text("-42 dB (min) … 0 dB (max)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Divider()

            // Mode
            settingRow("Audio Mode") {
                Picker("", selection: modeBinding(device)) {
                    ForEach(SennheiserDevice.AudioMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
                .labelsHidden()
            }
        }
        .padding()
    }

    private func settingRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .frame(width: 100, alignment: .trailing)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func submitName(_ device: SennheiserDevice) {
        let name = editingName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        appState.setDeviceName(device, name: name)
        isEditingName = false
    }

    private func submitFrequency(_ device: SennheiserDevice) {
        guard let mhz = Double(editingFrequency.replacingOccurrences(of: ",", with: ".")) else { return }
        let khz = Int(mhz * 1000)
        appState.setDeviceFrequency(device, frequencyKHz: khz)
        isEditingFrequency = false
    }

    private func muteBinding(_ device: SennheiserDevice) -> Binding<Bool> {
        Binding(
            get: { device.muted },
            set: { appState.setDeviceMute(device, muted: $0) }
        )
    }

    private func sensitivityBinding(_ device: SennheiserDevice) -> Binding<Double> {
        Binding(
            get: { Double(device.sensitivity) },
            set: { appState.setDeviceSensitivity(device, dB: Int($0)) }
        )
    }

    private func modeBinding(_ device: SennheiserDevice) -> Binding<SennheiserDevice.AudioMode> {
        Binding(
            get: { device.mode },
            set: { appState.setDeviceMode(device, mode: $0) }
        )
    }
}
