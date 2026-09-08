import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showAddDevice = false

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
                Text("Transmitters")
                    .font(.headline)
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
                List(appState.devices) { device in
                    DeviceRow(device: device)
                }
            }

            Divider()

            if let showFile = appState.showFile {
                VStack(alignment: .leading, spacing: 4) {
                    Label(showFile.fileName, systemImage: "doc.fill")
                        .font(.caption)
                        .lineLimit(1)
                    Text("\(showFile.entries.count) frequencies")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
            if appState.showFile != nil {
                FrequencyAssignmentView()
            } else {
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
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
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
