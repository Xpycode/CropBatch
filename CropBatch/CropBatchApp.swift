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
            // MARK: - File Menu
            CommandGroup(replacing: .newItem) {
                Button("Import Images...") {
                    appState.showImportPanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                Divider()

                Button("Export...") {
                    showExportPanel()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!appState.canExport)

                Divider()

                Button("Clear All") {
                    appState.clearAll()
                }
                .disabled(appState.images.isEmpty)
            }

            // MARK: - Edit Menu
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

            CommandGroup(after: .pasteboard) {
                Divider()

                Button("Copy Cropped Image") {
                    copyActiveImageToClipboard()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(appState.activeImage == nil || !appState.cropSettings.hasAnyCrop)

                Divider()

                Button("Select All") {
                    appState.selectedImageIDs = Set(appState.images.map { $0.id })
                }
                .keyboardShortcut("a", modifiers: .command)
                .disabled(appState.images.isEmpty)

                Button("Deselect All") {
                    appState.selectedImageIDs.removeAll()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(appState.selectedImageIDs.isEmpty)
            }

            // MARK: - View Menu (add to existing)
            CommandGroup(after: .toolbar) {
                Divider()

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

                Divider()

                Menu("Aspect Guide") {
                    Button("None") {
                        appState.showAspectRatioGuide = nil
                    }

                    Divider()

                    ForEach(AspectRatioGuide.allCases) { guide in
                        Button(guide.rawValue) {
                            appState.showAspectRatioGuide = guide
                        }
                    }
                }
            }

            // MARK: - Image Menu
            CommandMenu("Image") {
                Button("Previous Image") {
                    appState.selectPreviousImage()
                }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(appState.images.count < 2)

                Button("Next Image") {
                    appState.selectNextImage()
                }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(appState.images.count < 2)

                Divider()

                Button("Rotate Left") {
                    appState.rotateActiveImage(clockwise: false)
                }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(appState.activeImage == nil)

                Button("Rotate Right") {
                    appState.rotateActiveImage(clockwise: true)
                }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(appState.activeImage == nil)

                Divider()

                Button("Flip Horizontal") {
                    appState.flipActiveImage(horizontal: true)
                }
                .keyboardShortcut("h", modifiers: [.command, .option])
                .disabled(appState.activeImage == nil)

                Button("Flip Vertical") {
                    appState.flipActiveImage(horizontal: false)
                }
                .keyboardShortcut("v", modifiers: [.command, .option])
                .disabled(appState.activeImage == nil)

                Divider()

                Button("Reset Transform") {
                    appState.resetActiveImageTransform()
                }
                .disabled(appState.activeImageTransform.isIdentity)

                Divider()

                Button("Remove Selected") {
                    appState.removeImages(ids: appState.selectedImageIDs.isEmpty
                        ? (appState.activeImage.map { Set([$0.id]) } ?? Set())
                        : appState.selectedImageIDs)
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(appState.activeImage == nil && appState.selectedImageIDs.isEmpty)
            }

            // MARK: - Crop Menu
            CommandMenu("Crop") {
                Button("Reset Crop") {
                    appState.resetCropSettings()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!appState.cropSettings.hasAnyCrop)

                Divider()

                Menu("Link Mode") {
                    ForEach(EdgeLinkMode.allCases) { mode in
                        Button {
                            appState.edgeLinkMode = mode
                        } label: {
                            if appState.edgeLinkMode == mode {
                                Text("✓ \(mode.rawValue)")
                            } else {
                                Text("    \(mode.rawValue)")
                            }
                        }
                    }
                }

                Divider()

                Menu("Presets") {
                    Button("None (Reset)") {
                        appState.resetCropSettings()
                    }

                    Divider()

                    ForEach(PresetCategory.allCases) { category in
                        let categoryPresets = PresetManager.shared.allPresets.filter { $0.category == category }
                        if !categoryPresets.isEmpty {
                            Menu(category.rawValue) {
                                ForEach(categoryPresets) { preset in
                                    Button(preset.name) {
                                        appState.applyCropPreset(preset)
                                    }
                                }
                            }
                        }
                    }
                }

                Divider()

                // Quick crop adjustments
                Button("Increase Top") {
                    appState.adjustCrop(edge: .top, delta: 1)
                }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(appState.images.isEmpty)

                Button("Decrease Top") {
                    appState.adjustCrop(edge: .top, delta: -1)
                }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option, .shift])
                .disabled(appState.cropSettings.cropTop == 0)

                Button("Increase Bottom") {
                    appState.adjustCrop(edge: .bottom, delta: 1)
                }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(appState.images.isEmpty)

                Button("Decrease Bottom") {
                    appState.adjustCrop(edge: .bottom, delta: -1)
                }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option, .shift])
                .disabled(appState.cropSettings.cropBottom == 0)
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

    private func showExportPanel() {
        let panel = NSOpenPanel()
        panel.title = "Choose Export Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let outputDirectory = panel.url else { return }
            Task {
                do {
                    let results = try await appState.processAndExport(to: outputDirectory)
                    if !NSApp.isActive {
                        appState.sendExportNotification(count: results.count)
                    }
                } catch {
                    print("Export failed: \(error)")
                }
            }
        }
    }
}
