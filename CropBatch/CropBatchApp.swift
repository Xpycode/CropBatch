import SwiftUI

@main
struct CropBatchApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import Images...") {
                    appState.showFileImporter = true
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            // Zoom commands
            CommandMenu("View") {
                Button("Actual Size (100%)") {
                    appState.zoomMode = .actualSize
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Fit to View") {
                    appState.zoomMode = .fit
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Fit Width") {
                    appState.zoomMode = .fitWidth
                }
                .keyboardShortcut("3", modifiers: .command)

                Button("Fit Height") {
                    appState.zoomMode = .fitHeight
                }
                .keyboardShortcut("4", modifiers: .command)
            }
        }
    }
}
