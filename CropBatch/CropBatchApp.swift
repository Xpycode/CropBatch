import SwiftUI
import AppKit

@main
struct CropBatchApp: App {
    @State private var appState = AppState()
    @State private var isCLIMode = false

    init() {
        // Check if launched with CLI arguments
        if CLIHandler.hasArguments() {
            isCLIMode = true
            Task {
                let exitCode = await CLIHandler.run()
                exit(exitCode)
            }
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(appState)
        }
        .windowStyle(.automatic)
        .windowResizability(.contentSize)
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import Images...") {
                    appState.showFileImporter = true
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            // Undo/Redo commands
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    appState.undo()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!appState.canUndo)

                Button("Redo") {
                    appState.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!appState.canRedo)
            }

            // Copy command
            CommandGroup(replacing: .pasteboard) {
                Button("Copy Cropped Image") {
                    copyActiveImageToClipboard()
                }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(appState.activeImage == nil || !appState.cropSettings.hasAnyCrop)
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

                Divider()

                Toggle("Show Before/After", isOn: Binding(
                    get: { appState.showBeforeAfter },
                    set: { appState.showBeforeAfter = $0 }
                ))
                .keyboardShortcut("b", modifiers: .command)
            }
        }
    }

    private func copyActiveImageToClipboard() {
        guard let activeImage = appState.activeImage else { return }

        do {
            let croppedImage = try ImageCropService.crop(
                activeImage.originalImage,
                with: appState.cropSettings
            )

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([croppedImage])
        } catch {
            print("Failed to copy image: \(error)")
        }
    }
}
