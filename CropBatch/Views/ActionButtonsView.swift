import SwiftUI
import AppKit
import UniformTypeIdentifiers
import UserNotifications

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

    private var imagesToProcess: [ImageItem] {
        appState.selectedImageIDs.isEmpty
            ? appState.images
            : appState.selectedImages
    }

    private var wouldOverwriteAny: Bool {
        imagesToProcess.contains { appState.exportSettings.wouldOverwriteOriginal(for: $0.url) }
    }

    private var canExport: Bool {
        !appState.images.isEmpty &&
        (appState.cropSettings.hasAnyCrop || appState.hasAnyBlurRegions || appState.hasAnyTransforms || appState.exportSettings.resizeSettings.isEnabled || appState.exportSettings.renameSettings.mode == .pattern) &&
        !appState.isProcessing &&
        !wouldOverwriteAny
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
            .disabled(!canExport)

            // Warning messages
            if !appState.cropSettings.hasAnyCrop && !appState.hasAnyBlurRegions && !appState.hasAnyTransforms && !appState.exportSettings.resizeSettings.isEnabled && appState.exportSettings.renameSettings.mode != .pattern && !appState.images.isEmpty {
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

    /// Send system notification for export completion
    private func sendExportNotification(count: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Export Complete"
        content.body = "Successfully exported \(count) cropped images"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func processImages(_ images: [ImageItem], to outputDirectory: URL) async {
        await MainActor.run {
            appState.isProcessing = true
            appState.processingProgress = 0
        }

        // Create export settings with the selected output directory
        var exportSettings = appState.exportSettings
        exportSettings.outputDirectory = .custom(outputDirectory)

        do {
            let results = try await ImageCropService.batchCrop(
                items: images,
                cropSettings: appState.cropSettings,
                exportSettings: exportSettings,
                transforms: appState.imageTransforms,
                blurRegions: appState.blurRegions
            ) { progress in
                appState.processingProgress = progress
            }

            await MainActor.run {
                appState.isProcessing = false
                exportedCount = results.count
                lastExportDirectory = outputDirectory
                showSuccessAlert = true

                // Send system notification if app is not active
                if !NSApp.isActive {
                    sendExportNotification(count: results.count)
                }
            }
        } catch {
            await MainActor.run {
                appState.isProcessing = false
                exportError = error.localizedDescription
                showErrorAlert = true
            }
        }
    }
}

#Preview {
    ActionButtonsView()
        .environment(AppState())
        .frame(width: 250)
        .padding()
}
