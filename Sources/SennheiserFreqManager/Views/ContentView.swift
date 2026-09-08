import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showAddDevice = false
    @State private var showFileImporter = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if appState.showFile != nil {
                FrequencyAssignmentView()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Sennheiser Freq Manager")
                        .font(.title2)
                    Text("Import a Wireless Workbench file (.shw) or add devices manually")
                        .foregroundStyle(.secondary)

                    Button("Open WWB Show File…") {
                        showFileImporter = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showFileImporter = true
                } label: {
                    Label("Open WWB File", systemImage: "doc.badge.plus")
                }

                Button {
                    appState.startDiscovery()
                } label: {
                    Label("Scan Network", systemImage: "network")
                }
                .disabled(appState.isScanning)

                Button {
                    showAddDevice = true
                } label: {
                    Label("Add Device", systemImage: "plus")
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.xml, .init(filenameExtension: "shw")!],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                if url.startAccessingSecurityScopedResource() {
                    appState.loadShowFile(url: url)
                    url.stopAccessingSecurityScopedResource()
                }
            }
        }
        .sheet(isPresented: $showAddDevice) {
            AddDeviceView()
        }
        .overlay(alignment: .bottom) {
            if !appState.statusMessage.isEmpty {
                StatusBar(message: appState.statusMessage)
            }
        }
    }

    private var sidebar: some View {
        List {
            Section("Transmitters") {
                if appState.devices.isEmpty {
                    Text("No devices")
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    ForEach(appState.devices) { device in
                        DeviceRow(device: device)
                    }
                }
            }

            if let showFile = appState.showFile {
                Section("WWB: \(showFile.fileName)") {
                    Label("\(showFile.entries.count) frequencies", systemImage: "waveform")
                    Label("\(showFile.activeEntries.count) active", systemImage: "checkmark.circle")
                    if !showFile.backupEntries.isEmpty {
                        Label("\(showFile.backupEntries.count) backup", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220)
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
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct StatusBar: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .padding(8)
    }
}
