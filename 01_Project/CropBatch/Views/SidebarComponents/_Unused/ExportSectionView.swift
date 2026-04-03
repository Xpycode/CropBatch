import SwiftUI

// MARK: - Export Section

struct ExportSectionView: View {
    @Environment(AppState.self) private var appState
    @State private var coordinator = ExportCoordinator()

    private var imagesToProcess: [ImageItem] {
        appState.selectedImageIDs.isEmpty ? appState.images : appState.selectedImages
    }

    var body: some View {
        @Bindable var state = appState

        VStack(alignment: .leading, spacing: 12) {
            // Format buttons
            VStack(spacing: 4) {
                Text("Format")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    ForEach(ExportFormat.allCases) { fmt in
                        Button {
                            appState.exportSettings.format = fmt
                            appState.markCustomSettings()
                        } label: {
                            Text(fmt.rawValue)
                                .font(.system(size: 10, weight: .medium))
                                .frame(minWidth: 36, minHeight: 22)
                        }
                        .buttonStyle(.bordered)
                        .tint(appState.exportSettings.format == fmt ? .accentColor : .secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Divider()

            // Naming buttons
            VStack(spacing: 4) {
                Text("Naming")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    ForEach(RenameMode.allCases) { mode in
                        Button {
                            appState.exportSettings.renameSettings.mode = mode
                            appState.markCustomSettings()
                        } label: {
                            Text(mode.rawValue)
                                .font(.system(size: 10, weight: .medium))
                                .frame(minHeight: 22)
                                .padding(.horizontal, 8)
                        }
                        .buttonStyle(.bordered)
                        .tint(appState.exportSettings.renameSettings.mode == mode ? .accentColor : .secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            // Output preview
            if let firstImage = appState.images.first {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(appState.exportSettings.outputFilename(for: firstImage.url))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            // Warning if nothing to export
            if !appState.canExport && !appState.images.isEmpty && !appState.isProcessing {
                Text("Apply crop, transform, or resize to export")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            // Export options (always visible)
            Divider()
            ExportOptionsExpandedView()

            // Export button - at bottom with padding
            Spacer().frame(height: 8)

            Button {
                coordinator.selectOutputFolderAndProcess(images: imagesToProcess)
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.down.fill")
                    Text(appState.selectedImageIDs.isEmpty
                         ? "Export All (\(appState.images.count))"
                         : "Export Selected (\(appState.selectedImageIDs.count))")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!appState.canExport)

            // Progress indicator
            if appState.isProcessing {
                VStack(spacing: 4) {
                    ProgressView(value: appState.processingProgress)
                        .progressViewStyle(.linear)
                    Text("Exporting \(Int(appState.processingProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear { coordinator.setAppState(appState) }
        .exportSheets(coordinator: coordinator, appState: appState, imagesToProcess: imagesToProcess)
    }
}
