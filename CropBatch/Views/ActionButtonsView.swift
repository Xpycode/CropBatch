import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ActionButtonsView: View {
    @Environment(AppState.self) private var appState
    @State private var showReviewSheet = false
    @State private var pendingOutputDirectory: URL?
    @State private var exportError: String?
    @State private var showErrorAlert = false
    @State private var showSuccessAlert = false
    @State private var exportedCount = 0
    @State private var reviewBeforeExport = true
    @State private var lastExportDirectory: URL?

    // Overwrite handling
    @State private var showOverwriteDialog = false
    @State private var existingFilesCount = 0
    @State private var pendingExportImages: [ImageItem] = []
    @State private var pendingExportDirectory: URL?
    @State private var dialogPresentationID = UUID()  // Forces dialog rebuild on each presentation

    private var imagesToProcess: [ImageItem] {
        appState.selectedImageIDs.isEmpty
            ? appState.images
            : appState.selectedImages
    }

    private var wouldOverwriteAny: Bool {
        imagesToProcess.contains { appState.exportSettings.wouldOverwriteOriginal(for: $0.url) }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Undo/Redo and Transform buttons
            HStack(spacing: 8) {
                Button {
                    appState.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .disabled(!appState.canUndo)
                .help("Undo (⌘Z)")

                Button {
                    appState.redo()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .disabled(!appState.canRedo)
                .help("Redo (⇧⌘Z)")

                Spacer()

                // Rotation buttons
                Button {
                    appState.rotateActiveImage(clockwise: false)
                } label: {
                    Label("Rotate Left", systemImage: "rotate.left")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .disabled(appState.activeImage == nil)
                .help("Rotate CCW (⌘[)")

                Button {
                    appState.rotateActiveImage(clockwise: true)
                } label: {
                    Label("Rotate Right", systemImage: "rotate.right")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .disabled(appState.activeImage == nil)
                .help("Rotate CW (⌘])")

                // Flip buttons
                Button {
                    appState.flipActiveImage(horizontal: true)
                } label: {
                    Label("Flip H", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .disabled(appState.activeImage == nil)
                .help("Flip Horizontal")

                Button {
                    appState.flipActiveImage(horizontal: false)
                } label: {
                    Label("Flip V", systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .disabled(appState.activeImage == nil)
                .help("Flip Vertical")
            }

            Divider()

            if appState.isProcessing {
                VStack(spacing: 8) {
                    ProgressView(value: appState.processingProgress)
                        .progressViewStyle(.linear)

                    Text("Processing \(Int(appState.processingProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Review toggle
            Toggle("Review before export", isOn: $reviewBeforeExport)
                .font(.caption)
                .toggleStyle(.checkbox)

            Button {
                selectOutputFolder()
            } label: {
                Label(
                    appState.selectedImageIDs.isEmpty
                        ? "Export All (\(appState.images.count))"
                        : "Export Selected (\(appState.selectedImageIDs.count))",
                    systemImage: "square.and.arrow.down"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!appState.canExport || wouldOverwriteAny)

            // Warning messages
            if !appState.images.isEmpty && !appState.canExport && !appState.isProcessing {
                Text("Apply crop, rotate, resize, or rename to export")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if wouldOverwriteAny {
                Text("Change suffix to avoid overwriting originals")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .sheet(isPresented: $showReviewSheet) {
            if let outputDir = pendingOutputDirectory {
                BatchReviewView(
                    images: imagesToProcess,
                    outputDirectory: outputDir
                ) { selectedImages in
                    Task {
                        await processImages(selectedImages, to: outputDir)
                        outputDir.stopAccessingSecurityScopedResource()
                    }
                }
                .environment(appState)
            }
        }
        .alert("Export Failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "Unknown error")
        }
        .alert("Export Complete", isPresented: $showSuccessAlert) {
            if let dir = lastExportDirectory {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir.path)
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Successfully exported \(exportedCount) cropped images")
        }
        .confirmationDialog(
            "Overwrite Existing Files?",
            isPresented: $showOverwriteDialog,
            titleVisibility: .visible
        ) {
            // Capture values BEFORE the Task to avoid race conditions
            // (dialog dismissal may clear state before Task starts)
            let images = pendingExportImages
            let directory = pendingExportDirectory

            Button("Overwrite", role: .destructive) {
                guard let dir = directory else { return }
                Task {
                    await executeExport(images, to: dir, rename: false)
                }
            }
            Button("Rename (add _1, _2...)") {
                guard let dir = directory else { return }
                Task {
                    await executeExport(images, to: dir, rename: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(existingFilesCount) file\(existingFilesCount == 1 ? "" : "s") already exist\(existingFilesCount == 1 ? "s" : "") in the destination folder.")
        }
        .id(dialogPresentationID)  // Force SwiftUI to rebuild dialog content on each presentation
        // Note: pending state is cleared in executeExport() after export completes,
        // NOT on dialog dismiss. This prevents a race where the onChange fires
        // before the button action captures the pending values.
    }

    /// Opens NSOpenPanel to select output folder
    private func selectOutputFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Export Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let outputDirectory = panel.url else { return }

            if reviewBeforeExport {
                // Show review sheet
                pendingOutputDirectory = outputDirectory
                showReviewSheet = true
            } else {
                // Direct export
                Task {
                    await processImages(imagesToProcess, to: outputDirectory)
                }
            }
        }
    }

    private func processImages(_ images: [ImageItem], to outputDirectory: URL) async {
        // Check for existing files before exporting
        var settings = appState.exportSettings
        settings.outputDirectory = .custom(outputDirectory)
        let existingFiles = settings.findExistingFiles(items: images)

        if !existingFiles.isEmpty {
            // Show confirmation dialog
            existingFilesCount = existingFiles.count
            pendingExportImages = images
            pendingExportDirectory = outputDirectory
            dialogPresentationID = UUID()  // Force dialog content rebuild
            showOverwriteDialog = true
        } else {
            // No conflicts, proceed directly
            await executeExport(images, to: outputDirectory, rename: false)
        }
    }

    private func executeExport(_ images: [ImageItem], to outputDirectory: URL, rename: Bool) async {
        // Clear pending state AFTER export completes (not on dialog dismiss)
        // This prevents race conditions where state is cleared before it's used
        defer {
            pendingExportImages = []
            pendingExportDirectory = nil
        }

        do {
            let results: [URL]

            if rename {
                // Export with renamed files to avoid overwriting
                results = try await appState.processAndExportWithRename(images: images, to: outputDirectory)
            } else {
                results = try await appState.processAndExport(images: images, to: outputDirectory)
            }

            exportedCount = results.count
            lastExportDirectory = outputDirectory
            showSuccessAlert = true

            // Send system notification if app is not active
            if !NSApp.isActive {
                appState.sendExportNotification(count: results.count)
            }
        } catch {
            exportError = error.localizedDescription
            showErrorAlert = true
        }
    }
}

#Preview {
    ActionButtonsView()
        .environment(AppState())
        .frame(width: 250)
        .padding()
}
