import SwiftUI

/// Coordinates export operations and manages related UI state
/// Extracted to eliminate duplication between ExportFooterView and ExportSectionView
@MainActor
@Observable
final class ExportCoordinator {
    // MARK: - Sheet/Alert State

    var showReviewSheet = false
    var pendingOutputDirectory: URL?
    var showErrorAlert = false
    var exportError: String?
    var showSuccessAlert = false
    var exportedCount = 0

    // MARK: - Overwrite Dialog State

    var showOverwriteDialog = false
    var existingFilesCount = 0
    var pendingExportImages: [ImageItem] = []
    var pendingExportDirectory: URL?
    var dialogPresentationID = UUID()

    // MARK: - Dependencies

    private weak var appState: AppState?

    init(appState: AppState? = nil) {
        self.appState = appState
    }

    func setAppState(_ appState: AppState) {
        self.appState = appState
    }

    // MARK: - Export Flow

    /// Shows folder picker and initiates review sheet (modal, sync)
    func selectOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Select output folder for cropped images"

        if panel.runModal() == .OK, let url = panel.url {
            pendingOutputDirectory = url
            showReviewSheet = true
        }
    }

    /// Shows folder picker and directly processes images (async, no review sheet)
    func selectOutputFolderAndProcess(images: [ImageItem]) {
        guard let appState else { return }

        let panel = NSOpenPanel()
        panel.title = "Choose Export Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        panel.begin { [weak self] response in
            guard response == .OK, let outputDirectory = panel.url else { return }
            Task { @MainActor [weak self] in
                await self?.processImagesWithConflictCheck(images, to: outputDirectory, appState: appState)
            }
        }
    }

    /// Checks for conflicts using ExportSettings method
    private func processImagesWithConflictCheck(_ images: [ImageItem], to outputDirectory: URL, appState: AppState) async {
        var settings = appState.exportSettings
        settings.outputDirectory = .custom(outputDirectory)
        let existingFiles = settings.findExistingFiles(items: images)

        if !existingFiles.isEmpty {
            existingFilesCount = existingFiles.count
            pendingExportImages = images
            pendingExportDirectory = outputDirectory
            dialogPresentationID = UUID()
            showOverwriteDialog = true
        } else {
            await executeExport(images, to: outputDirectory, rename: false)
        }
    }

    /// Checks for existing files and either exports or shows overwrite dialog
    /// Uses ExportSettings.findExistingFiles to properly handle rename patterns with indices
    func processImages(_ images: [ImageItem], to outputDirectory: URL) async {
        guard let appState else { return }

        // Use the same approach as processImagesWithConflictCheck to properly
        // check for conflicts with rename patterns (e.g., {filename}_{index})
        var settings = appState.exportSettings
        settings.outputDirectory = .custom(outputDirectory)
        let existingFiles = settings.findExistingFiles(items: images)

        if !existingFiles.isEmpty {
            pendingExportImages = images
            pendingExportDirectory = outputDirectory
            existingFilesCount = existingFiles.count
            dialogPresentationID = UUID()
            showOverwriteDialog = true
        } else {
            await executeExport(images, to: outputDirectory, rename: false)
        }
    }

    /// Performs the actual export operation
    func executeExport(_ images: [ImageItem], to outputDirectory: URL, rename: Bool) async {
        guard let appState else { return }

        do {
            let results: [URL]

            if rename {
                results = try await appState.processAndExportWithRename(images: images, to: outputDirectory)
            } else {
                results = try await appState.processAndExport(images: images, to: outputDirectory)
            }

            exportedCount = results.count
            showSuccessAlert = true
        } catch {
            exportError = error.localizedDescription
            showErrorAlert = true
        }
    }

    /// Called when overwrite dialog is dismissed
    func onOverwriteDialogDismissed() {
        pendingExportImages = []
        pendingExportDirectory = nil
    }

    /// Handles overwrite action
    func handleOverwrite() {
        guard let dir = pendingExportDirectory else { return }
        let images = pendingExportImages
        Task {
            await executeExport(images, to: dir, rename: false)
        }
    }

    /// Handles rename action
    func handleRename() {
        guard let dir = pendingExportDirectory else { return }
        let images = pendingExportImages
        Task {
            await executeExport(images, to: dir, rename: true)
        }
    }
}

// MARK: - View Modifier for Export Sheets/Alerts

extension View {
    /// Applies all export-related sheets and alerts using the coordinator
    func exportSheets(
        coordinator: ExportCoordinator,
        appState: AppState,
        imagesToProcess: [ImageItem]
    ) -> some View {
        self
            .sheet(isPresented: Binding(
                get: { coordinator.showReviewSheet },
                set: { coordinator.showReviewSheet = $0 }
            )) {
                if let outputDir = coordinator.pendingOutputDirectory {
                    BatchReviewView(images: imagesToProcess, outputDirectory: outputDir) { selectedImages in
                        Task {
                            await coordinator.processImages(selectedImages, to: outputDir)
                        }
                    }
                    .environment(appState)
                }
            }
            .alert("Export Complete", isPresented: Binding(
                get: { coordinator.showSuccessAlert },
                set: { coordinator.showSuccessAlert = $0 }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Successfully exported \(coordinator.exportedCount) images")
            }
            .alert("Export Failed", isPresented: Binding(
                get: { coordinator.showErrorAlert },
                set: { coordinator.showErrorAlert = $0 }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(coordinator.exportError ?? "Unknown error")
            }
            .confirmationDialog(
                "Overwrite Existing Files?",
                isPresented: Binding(
                    get: { coordinator.showOverwriteDialog },
                    set: { coordinator.showOverwriteDialog = $0 }
                ),
                titleVisibility: .visible
            ) {
                Button("Overwrite", role: .destructive) {
                    coordinator.handleOverwrite()
                }
                Button("Rename (add _1, _2...)") {
                    coordinator.handleRename()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(coordinator.existingFilesCount) file\(coordinator.existingFilesCount == 1 ? "" : "s") already exist\(coordinator.existingFilesCount == 1 ? "s" : "") in the destination folder.")
            }
            .id(coordinator.dialogPresentationID)
            .onChange(of: coordinator.showOverwriteDialog) { _, isShowing in
                if !isShowing {
                    coordinator.onOverwriteDialogDismissed()
                }
            }
    }
}
