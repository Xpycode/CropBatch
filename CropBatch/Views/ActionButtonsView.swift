import SwiftUI
import UniformTypeIdentifiers

struct ActionButtonsView: View {
    @Environment(AppState.self) private var appState
    @State private var showExportPanel = false
    @State private var exportError: String?
    @State private var showErrorAlert = false
    @State private var showSuccessAlert = false
    @State private var exportedCount = 0

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
        appState.cropSettings.hasAnyCrop &&
        !appState.isProcessing &&
        !wouldOverwriteAny
    }

    var body: some View {
        VStack(spacing: 12) {
            if appState.isProcessing {
                VStack(spacing: 8) {
                    ProgressView(value: appState.processingProgress)
                        .progressViewStyle(.linear)

                    Text("Processing \(Int(appState.processingProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                showExportPanel = true
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
            if !appState.cropSettings.hasAnyCrop && !appState.images.isEmpty {
                Text("Set crop values to enable export")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if wouldOverwriteAny {
                Text("Change suffix to avoid overwriting originals")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .fileImporter(
            isPresented: $showExportPanel,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let outputDirectory = urls.first {
                    guard outputDirectory.startAccessingSecurityScopedResource() else {
                        exportError = "Cannot access the selected folder"
                        showErrorAlert = true
                        return
                    }
                    Task {
                        await processImages(to: outputDirectory)
                        outputDirectory.stopAccessingSecurityScopedResource()
                    }
                }
            case .failure(let error):
                exportError = error.localizedDescription
                showErrorAlert = true
            }
        }
        .alert("Export Failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "Unknown error")
        }
        .alert("Export Complete", isPresented: $showSuccessAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Successfully exported \(exportedCount) cropped images")
        }
    }

    private func processImages(to outputDirectory: URL) async {
        await MainActor.run {
            appState.isProcessing = true
            appState.processingProgress = 0
        }

        // Create export settings with the selected output directory
        var exportSettings = appState.exportSettings
        exportSettings.outputDirectory = .custom(outputDirectory)

        do {
            let results = try await ImageCropService.batchCrop(
                items: imagesToProcess,
                cropSettings: appState.cropSettings,
                exportSettings: exportSettings
            ) { progress in
                appState.processingProgress = progress
            }

            await MainActor.run {
                appState.isProcessing = false
                exportedCount = results.count
                showSuccessAlert = true
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
