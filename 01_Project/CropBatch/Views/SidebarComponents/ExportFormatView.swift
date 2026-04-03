import SwiftUI

// MARK: - Export Format (Always Visible)

struct ExportFormatView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        // Format selection
        LabeledContent("Format") {
            HStack(spacing: 4) {
                ForEach(ExportFormat.allCases) { fmt in
                    Button {
                        appState.exportSettings.format = fmt
                        appState.markCustomSettings()
                    } label: {
                        Text(fmt.rawValue)
                            .frame(minWidth: 32)
                    }
                    .buttonStyle(.bordered)
                    .tint(appState.exportSettings.format == fmt ? .accentColor : .secondary)
                }
            }
            .controlSize(.small)
            .disabled(appState.cropSettings.cornerRadiusEnabled)
        }

        if appState.cropSettings.cornerRadiusEnabled {
            Text("PNG required for corner radius")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        // Naming selection (hidden in save-in-place mode)
        if !appState.exportSettings.outputDirectory.isOverwriteMode {
            LabeledContent("Naming") {
                Picker("", selection: Binding(
                    get: { appState.exportSettings.renameSettings.mode },
                    set: { appState.exportSettings.renameSettings.mode = $0; appState.markCustomSettings() }
                )) {
                    ForEach(RenameMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
        }

        // Save in Place toggle
        SaveInPlaceSection()

        // Output preview (hidden in save-in-place mode)
        if !appState.exportSettings.outputDirectory.isOverwriteMode,
           let firstImage = appState.images.first {
            LabeledContent("Output") {
                Text(appState.exportSettings.outputFilename(for: firstImage.url))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}
