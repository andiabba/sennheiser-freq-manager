import SwiftUI

struct DeviceDetailView: View {
    @ObservedObject var appState: AppState
    let deviceID: String

    @State private var editingName = ""
    @State private var editingFrequency = ""
    @State private var editingBank = ""
    @State private var editingChannel = ""
    @State private var isEditingName = false
    @State private var isEditingFrequency = false
    @State private var isEditingBank = false
    @State private var isEditingChannel = false

    private var device: SennheiserDevice? {
        appState.devices.first { $0.id == deviceID }
    }

    var body: some View {
        if let device = device {
            ScrollView {
                VStack(spacing: 0) {
                    deviceHeader(device)
                    Divider()
                    txSettings(device)
                    Divider().padding(.vertical, 8)
                    rxSyncSettings(device)
                    Spacer(minLength: 20)
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

    // MARK: - Header

    private func deviceHeader(_ device: SennheiserDevice) -> some View {
        VStack(spacing: 8) {
            HStack {
                Circle()
                    .fill(device.isOnline ? .green : .red)
                    .frame(width: 10, height: 10)
                Text(device.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                if device.rfMute {
                    Text("MUTED")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .cornerRadius(4)
                }
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

    // MARK: - TX Settings

    private func txSettings(_ device: SennheiserDevice) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transmitter Settings")
                .font(.headline)
                .padding(.top, 4)

            // Name
            settingRow("Name") {
                editableText(
                    value: device.name,
                    editing: $editingName,
                    isEditing: $isEditingName,
                    onSubmit: { appState.setDeviceName(device, name: $0) }
                )
            }

            Divider()

            // Bank
            settingRow("Bank") {
                editableInt(
                    value: device.bank,
                    editing: $editingBank,
                    isEditing: $isEditingBank,
                    onSubmit: { appState.setDeviceBank(device, bank: $0) }
                )
            }

            Divider()

            // Channel
            settingRow("Channel") {
                editableInt(
                    value: device.channel,
                    editing: $editingChannel,
                    isEditing: $isEditingChannel,
                    onSubmit: { appState.setDeviceChannel(device, channel: $0) }
                )
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

            // Sensitivity
            settingRow("Sensitivity") {
                HStack {
                    Text("\(device.sensitivity) dB")
                        .monospacedDigit()
                        .frame(width: 55, alignment: .trailing)
                    Slider(
                        value: Binding(
                            get: { Double(device.sensitivity) },
                            set: { appState.setDeviceSensitivity(device, dB: Int($0)) }
                        ),
                        in: -42...0,
                        step: 3
                    )
                    .frame(maxWidth: 200)
                }
            }

            Divider()

            // Mode
            settingRow("Mode") {
                Picker("", selection: Binding(
                    get: { device.mode },
                    set: { appState.setDeviceMode(device, mode: $0) }
                )) {
                    ForEach(SennheiserDevice.AudioMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
                .labelsHidden()
            }

            Divider()

            // Auto Lock
            settingRow("Auto Lock") {
                Toggle(device.autoLock ? "Locked" : "Unlocked", isOn: Binding(
                    get: { device.autoLock },
                    set: { appState.setDeviceAutoLock(device, locked: $0) }
                ))
                .toggleStyle(.switch)
            }

            Divider()

            // RF Mute
            settingRow("RF Mute") {
                Toggle(device.rfMute ? "Muted" : "Active", isOn: Binding(
                    get: { device.rfMute },
                    set: { appState.setDeviceMute(device, muted: $0) }
                ))
                .toggleStyle(.switch)
            }

            Divider()

            // RF Power
            settingRow("RF Power") {
                Picker("", selection: Binding(
                    get: { device.rfPower },
                    set: { appState.setDeviceRfPower(device, mW: $0) }
                )) {
                    ForEach(SennheiserDevice.rfPowerLevels, id: \.self) { mw in
                        Text("\(mw) mW").tag(mw)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
                .labelsHidden()
            }

            Divider()

            // Warning AF Peak
            settingRow("Warn AF Peak") {
                Toggle(device.warningAfPeak ? "On" : "Off", isOn: Binding(
                    get: { device.warningAfPeak },
                    set: { appState.setDeviceWarningAfPeak(device, enabled: $0) }
                ))
                .toggleStyle(.switch)
            }

            Divider()

            // Warning RF Mute
            settingRow("Warn RF Mute") {
                Toggle(device.warningRfMute ? "On" : "Off", isOn: Binding(
                    get: { device.warningRfMute },
                    set: { appState.setDeviceWarningRfMute(device, enabled: $0) }
                ))
                .toggleStyle(.switch)
            }
        }
        .padding()
    }

    // MARK: - RX Sync Settings

    private func rxSyncSettings(_ device: SennheiserDevice) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("RX Sync Settings")
                .font(.headline)
                .padding(.top, 4)

            // RX Auto Lock
            settingRow("Auto Lock") {
                Toggle(device.rxAutoLock ? "Locked" : "Unlocked", isOn: Binding(
                    get: { device.rxAutoLock },
                    set: { appState.setRxAutoLock(device, locked: $0) }
                ))
                .toggleStyle(.switch)
            }

            Divider()

            // Balance
            settingRow("Balance") {
                HStack {
                    Text("L")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { Double(device.rxBalance) },
                            set: { appState.setRxBalance(device, value: Int($0)) }
                        ),
                        in: -12...12,
                        step: 1
                    )
                    .frame(maxWidth: 200)
                    Text("R")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(device.rxBalance)")
                        .monospacedDigit()
                        .frame(width: 30, alignment: .trailing)
                }
            }

            Divider()

            // RX Mode
            settingRow("Mode") {
                Picker("", selection: Binding(
                    get: { device.rxMode },
                    set: { appState.setRxMode(device, mode: $0) }
                )) {
                    ForEach(SennheiserDevice.AudioMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
                .labelsHidden()
            }

            Divider()

            // Limiter
            settingRow("Limiter") {
                Toggle(device.rxLimiter ? "On" : "Off", isOn: Binding(
                    get: { device.rxLimiter },
                    set: { appState.setRxLimiter(device, enabled: $0) }
                ))
                .toggleStyle(.switch)
            }

            Divider()

            // High Boost
            settingRow("High Boost") {
                Toggle(device.rxHighBoost ? "On" : "Off", isOn: Binding(
                    get: { device.rxHighBoost },
                    set: { appState.setRxHighBoost(device, enabled: $0) }
                ))
                .toggleStyle(.switch)
            }

            Divider()

            // Squelch
            settingRow("Squelch") {
                HStack {
                    Text("\(device.rxSquelch)")
                        .monospacedDigit()
                        .frame(width: 30, alignment: .trailing)
                    Slider(
                        value: Binding(
                            get: { Double(device.rxSquelch) },
                            set: { appState.setRxSquelch(device, value: Int($0)) }
                        ),
                        in: 0...36,
                        step: 1
                    )
                    .frame(maxWidth: 200)
                }
            }
        }
        .padding()
    }

    // MARK: - Helpers

    private func settingRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center) {
            Text(label)
                .frame(width: 110, alignment: .trailing)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func editableText(
        value: String,
        editing: Binding<String>,
        isEditing: Binding<Bool>,
        onSubmit: @escaping (String) -> Void
    ) -> some View {
        Group {
            if isEditing.wrappedValue {
                HStack {
                    TextField("", text: editing)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                        .onSubmit {
                            let v = editing.wrappedValue.trimmingCharacters(in: .whitespaces)
                            guard !v.isEmpty else { return }
                            onSubmit(v)
                            isEditing.wrappedValue = false
                        }
                    Button("Set") {
                        let v = editing.wrappedValue.trimmingCharacters(in: .whitespaces)
                        guard !v.isEmpty else { return }
                        onSubmit(v)
                        isEditing.wrappedValue = false
                    }
                    .buttonStyle(.bordered)
                    Button("Cancel") { isEditing.wrappedValue = false }
                        .buttonStyle(.bordered)
                }
            } else {
                HStack {
                    Text(value)
                    Spacer()
                    Button("Edit") {
                        editing.wrappedValue = value
                        isEditing.wrappedValue = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func editableInt(
        value: Int?,
        editing: Binding<String>,
        isEditing: Binding<Bool>,
        onSubmit: @escaping (Int) -> Void
    ) -> some View {
        Group {
            if isEditing.wrappedValue {
                HStack {
                    TextField("", text: editing)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onSubmit {
                            guard let v = Int(editing.wrappedValue) else { return }
                            onSubmit(v)
                            isEditing.wrappedValue = false
                        }
                    Button("Set") {
                        guard let v = Int(editing.wrappedValue) else { return }
                        onSubmit(v)
                        isEditing.wrappedValue = false
                    }
                    .buttonStyle(.bordered)
                    Button("Cancel") { isEditing.wrappedValue = false }
                        .buttonStyle(.bordered)
                }
            } else {
                HStack {
                    Text(value != nil ? "\(value!)" : "—")
                        .monospacedDigit()
                    Spacer()
                    Button("Edit") {
                        editing.wrappedValue = value != nil ? "\(value!)" : ""
                        isEditing.wrappedValue = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func submitFrequency(_ device: SennheiserDevice) {
        guard let mhz = Double(editingFrequency.replacingOccurrences(of: ",", with: ".")) else { return }
        let khz = Int(mhz * 1000)
        appState.setDeviceFrequency(device, frequencyKHz: khz)
        isEditingFrequency = false
    }
}
