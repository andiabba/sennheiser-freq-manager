import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var scanManager = RFScanManager()
    @State private var showAddDevice = false
    @State private var selectedDeviceID: String?
    @State private var showRFScan = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detailView
        }
        .sheet(isPresented: $showAddDevice) {
            AddDeviceView()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    selectedDeviceID = nil
                    showRFScan = false
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.caption)
                        Text("Transmitters")
                            .font(.headline)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Button {
                    showAddDevice = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)

                Button {
                    appState.startDiscovery()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(appState.isScanning)
            }
            .padding(12)

            Divider()

            if appState.devices.isEmpty {
                VStack {
                    Spacer()
                    Text("No devices found")
                        .foregroundStyle(.secondary)
                    Text("Add manually or scan network")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(selection: Binding(
                    get: { selectedDeviceID },
                    set: { newID in
                        selectedDeviceID = newID
                        if newID != nil { showRFScan = false }
                    }
                )) {
                    ForEach(appState.devices) { device in
                        DeviceRow(device: device)
                            .tag(device.id)
                    }
                }
                .listStyle(.sidebar)
            }

            Divider()

            // RF Explorer Scan button
            Button {
                showRFScan = true
                selectedDeviceID = nil
            } label: {
                HStack {
                    Image(systemName: "wave.3.right")
                        .foregroundColor(.accentColor)
                    Text("RF Scan")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    if scanManager.isScanning {
                        ProgressView()
                            .controlSize(.small)
                    } else if showRFScan {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(12)

            if let showFile = appState.showFile {
                Button {
                    showRFScan = false
                    selectedDeviceID = nil
                } label: {
                    HStack {
                        Image(systemName: "doc.fill")
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(showFile.fileName)
                                .font(.caption)
                                .lineLimit(1)
                            Text("\(showFile.entries.count) frequencies")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedDeviceID == nil && !showRFScan {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(12)
            }

            if !appState.statusMessage.isEmpty {
                Text(appState.statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .frame(width: 240)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var detailView: some View {
        Group {
            if let deviceID = selectedDeviceID,
               appState.devices.contains(where: { $0.id == deviceID }) {
                DeviceDetailView(appState: appState, deviceID: deviceID)
            } else if showRFScan {
                RFScanView(scanManager: scanManager)
            } else if appState.showFile != nil {
                FrequencyAssignmentView()
            } else {
                welcomeView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var welcomeView: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Sennheiser Freq Manager")
                .font(.title2)
                .fontWeight(.medium)
            Text("Open a Wireless Workbench show file (.shw)\nto load coordinated frequencies")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Open WWB File…") {
                openFilePanel()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            HStack(spacing: 12) {
                Button("Scan Network") {
                    appState.startDiscovery()
                }
                .disabled(appState.isScanning)

                Button("Add Device…") {
                    showAddDevice = true
                }
            }

            Divider()
                .frame(width: 200)
                .padding(.vertical, 4)

            Button("RF Explorer Scan…") {
                showRFScan = true
            }
        }
    }

    private func openFilePanel() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["shw", "xml"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a Wireless Workbench show file (.shw)"

        if panel.runModal() == .OK, let url = panel.url {
            appState.loadShowFile(url: url)
        }
    }
}

struct DeviceRow: View {
    let device: SennheiserDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Circle()
                    .fill(device.isOnline ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(device.name)
                    .fontWeight(.medium)
            }
            HStack {
                Text(device.host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(device.frequencyDisplayString)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
