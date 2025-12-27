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
        }
    }
}
