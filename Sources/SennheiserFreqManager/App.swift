import SwiftUI

let appState = AppState()

@main
struct SennheiserFreqManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open WWB File…") {
                    AppDelegate.openFile()
                }
                .keyboardShortcut("o")
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    static func openFile() {
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
