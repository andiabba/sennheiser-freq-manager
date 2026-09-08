import SwiftUI

struct AddDeviceView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var host = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Device Manually")
                .font(.headline)

            Form {
                TextField("Name", text: $name, prompt: Text("e.g. IEM Band 1"))
                TextField("IP Address", text: $host, prompt: Text("e.g. 192.168.1.100"))
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    let deviceName = name.isEmpty ? host : name
                    appState.addManualDevice(name: deviceName, host: host)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(host.isEmpty)
            }
        }
        .padding()
        .frame(width: 350)
    }
}
