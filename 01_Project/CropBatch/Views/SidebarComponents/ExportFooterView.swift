import SwiftUI
import UniformTypeIdentifiers

// MARK: - Export Footer (Sticky)

struct ExportFooterView: View {
    @Environment(AppState.self) private var appState
    @State private var coordinator = ExportCoordinator()

    private var imagesToProcess: [ImageItem] {
        if appState.selectedImageIDs.isEmpty {
            return appState.images
        } else {
            return appState.images.filter { appState.selectedImageIDs.contains($0.id) }
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Divider()

            // File size estimate
            if !appState.images.isEmpty {
                FileSizeEstimateView()
            }

            // Warning if nothing to export
            if !appState.canExport && !appState.images.isEmpty && !appState.isProcessing {
                Label("Apply crop, transform, or resize to export", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            // Export button - changes behavior based on Save in Place mode
            if appState.exportSettings.outputDirectory.isOverwriteMode {
                // Save in Place mode - no folder picker, direct confirmation
                Button {
                    coordinator.showSaveInPlaceConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text(appState.selectedImageIDs.isEmpty
                             ? "Save in Place (\(appState.images.count))"
                             : "Save in Place (\(appState.selectedImageIDs.count))")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .disabled(!appState.canExport || appState.exportSettings.validateOverwriteMode(
                    cornerRadiusEnabled: appState.cropSettings.cornerRadiusEnabled,
                    items: imagesToProcess
                ) != nil)
            } else {
                // Normal export - folder picker
                Button {
                    coordinator.selectOutputFolder()
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down.fill")
                        Text(appState.selectedImageIDs.isEmpty
                             ? "Export All (\(appState.images.count))"
                             : "Export Selected (\(appState.selectedImageIDs.count))")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!appState.canExport)
            }

            // Progress indicator
            if appState.isProcessing {
                ProgressView(value: appState.processingProgress) {
                    Text("Exporting \(Int(appState.processingProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .progressViewStyle(.linear)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .onAppear { coordinator.setAppState(appState) }
        .exportSheets(coordinator: coordinator, appState: appState, imagesToProcess: imagesToProcess)
    }
}
