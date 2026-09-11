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
                HStack {
                    Text(device.bankDisplayString)
                        .monospacedDigit()
                    Spacer()
                    Picker("", selection: Binding(
                        get: { device.bank ?? 1 },
                        set: { appState.setDeviceBank(device, bank: $0) }
                    )) {
                        ForEach(1...20, id: \.self) { b in
                            Text("\(b)").tag(b)
                        }
                        ForEach(1...6, id: \.self) { u in
                            Text("U\(u)").tag(20 + u)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 100)
                    .labelsHidden()
                }
            }

            Divider()

            // Channel
            settingRow("Channel") {
                HStack {
                    Text(device.channel != nil ? "\(device.channel!)" : "—")
                        .monospacedDigit()
                    Spacer()
                    Picker("", selection: Binding(
                        get: { device.channel ?? 1 },
                        set: { appState.setDeviceChannel(device, channel: $0) }
                    )) {
                        ForEach(SennheiserDevice.channelRange, id: \.self) { ch in
                            Text("\(ch)").tag(ch)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 80)
                    .labelsHidden()
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

            // Sensitivity (0 to -42, step 3)
            settingRow("Sensitivity") {
                HStack {
                    Picker("", selection: Binding(
                        get: { device.sensitivity },
                        set: { appState.setDeviceSensitivity(device, dB: $0) }
                    )) {
                        ForEach(SennheiserDevice.sensitivityValues, id: \.self) { v in
                            Text("\(v) dB").tag(v)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 100)
                    .labelsHidden()
                }
            }

            Divider()

            // Mode (Mono / Stereo)
            settingRow("Mode") {
                Picker("", selection: Binding(
                    get: { device.mode },
                    set: { appState.setDeviceMode(device, mode: $0) }
                )) {
                    ForEach(SennheiserDevice.TxMode.allCases, id: \.self) { mode in
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
                Toggle(device.autoLock ? "On" : "Off", isOn: Binding(
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

            // RF Power (10 / 30 / 50 mW)
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
            HStack {
                Text("RX Sync Settings")
                    .font(.headline)
                Spacer()
                Text("Sync")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 40)
            }
            .padding(.top, 4)

            // Auto Lock
            syncSettingRow("Auto Lock", synced: device.rxAutoLockSync, onSyncToggle: {
                appState.setRxAutoLockSync(device, enabled: $0)
            }) {
                Toggle(device.rxAutoLock ? "On" : "Off", isOn: Binding(
                    get: { device.rxAutoLock },
                    set: { appState.setRxAutoLock(device, locked: $0) }
                ))
                .toggleStyle(.switch)
            }

            Divider()

            // Balance (L15...L=R...R15)
            syncSettingRow("Balance", synced: device.rxBalanceSync, onSyncToggle: {
                appState.setRxBalanceSync(device, enabled: $0)
            }) {
                HStack {
                    Text("L")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { Double(device.rxBalance) },
                            set: { appState.setRxBalance(device, value: Int($0)) }
                        ),
                        in: -15...15,
                        step: 1
                    )
                    .frame(maxWidth: 200)
                    Text("R")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(device.balanceDisplayString)
                        .monospacedDigit()
                        .frame(width: 45, alignment: .trailing)
                }
            }

            Divider()

            // RX Mode (Stereo / Focus)
            syncSettingRow("Mode", synced: device.rxModeSync, onSyncToggle: {
                appState.setRxModeSync(device, enabled: $0)
            }) {
                Picker("", selection: Binding(
                    get: { device.rxMode },
                    set: { appState.setRxMode(device, mode: $0) }
                )) {
                    ForEach(SennheiserDevice.RxMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
                .labelsHidden()
            }

            Divider()

            // Limiter (Off / -18 / -12 / -6 dB)
            syncSettingRow("Limiter", synced: device.rxLimiterSync, onSyncToggle: {
                appState.setRxLimiterSync(device, enabled: $0)
            }) {
                Picker("", selection: Binding(
                    get: { device.rxLimiter },
                    set: { appState.setRxLimiter(device, value: $0) }
                )) {
                    Text("Off").tag(0)
                    Text("-18 dB").tag(-18)
                    Text("-12 dB").tag(-12)
                    Text("-6 dB").tag(-6)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
                .labelsHidden()
            }

            Divider()

            // High Boost
            syncSettingRow("High Boost", synced: device.rxHighBoostSync, onSyncToggle: {
                appState.setRxHighBoostSync(device, enabled: $0)
            }) {
                Toggle(device.rxHighBoost ? "On (+8 dB @ 8 kHz)" : "Off", isOn: Binding(
                    get: { device.rxHighBoost },
                    set: { appState.setRxHighBoost(device, enabled: $0) }
                ))
                .toggleStyle(.switch)
            }

            Divider()

            // Squelch (5 to 25 dBµV, step 2)
            syncSettingRow("Squelch", synced: device.rxSquelchSync, onSyncToggle: {
                appState.setRxSquelchSync(device, enabled: $0)
            }) {
                Picker("", selection: Binding(
                    get: { device.rxSquelch },
                    set: { appState.setRxSquelch(device, value: $0) }
                )) {
                    ForEach(SennheiserDevice.squelchValues, id: \.self) { v in
                        Text("\(v) dBµV").tag(v)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 120)
                .labelsHidden()
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

    private func syncSettingRow<Content: View>(
        _ label: String,
        synced: Bool,
        onSyncToggle: @escaping (Bool) -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center) {
            Text(label)
                .frame(width: 110, alignment: .trailing)
                .foregroundStyle(.secondary)
            if synced {
                content()
            } else {
                Text("Ignore")
                    .foregroundStyle(.tertiary)
                    .italic()
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { synced },
                set: { onSyncToggle($0) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .frame(width: 40)
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
                Text(value)
                    .onTapGesture(count: 2) {
                        editing.wrappedValue = value
                        isEditing.wrappedValue = true
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
