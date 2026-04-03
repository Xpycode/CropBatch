import SwiftUI

// MARK: - Export Options Expanded

struct ExportOptionsExpandedView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        VStack(alignment: .leading, spacing: 12) {
            // Quality slider (for JPEG/HEIC/WebP)
            if appState.exportSettings.format.supportsCompression {
                HStack {
                    Text("Quality")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { appState.exportSettings.quality },
                        set: { appState.exportSettings.quality = $0; appState.markCustomSettings() }
                    ), in: 0.1...1.0, step: 0.05)
                    .controlSize(.small)
                    Text("\(Int(appState.exportSettings.quality * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 35)
                }
            }

            // Suffix field (when using Keep Original naming)
            if appState.exportSettings.renameSettings.mode == .keepOriginal {
                HStack {
                    Text("Suffix")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField("_cropped", text: Binding(
                        get: { appState.exportSettings.suffix },
                        set: { appState.exportSettings.suffix = $0; appState.markCustomSettings() }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                }
            }

            // Pattern field (when using Pattern naming)
            if appState.exportSettings.renameSettings.mode == .pattern {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Pattern")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        TextField("{name}_{counter}", text: Binding(
                            get: { appState.exportSettings.renameSettings.pattern },
                            set: { appState.exportSettings.renameSettings.pattern = $0; appState.markCustomSettings() }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                        .font(.system(size: 11, design: .monospaced))
                    }

                    // Token buttons
                    HStack(spacing: 4) {
                        ForEach(RenameSettings.availableTokens, id: \.token) { token in
                            Button(token.token) {
                                appState.exportSettings.renameSettings.pattern += token.token
                                appState.markCustomSettings()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .help(token.description)
                        }
                    }
                }
            }

            Divider()

            // Resize settings
            ResizeSettingsSection()

            Divider()

            // Watermark settings
            WatermarkSettingsSection()

            Divider()

            // File size estimate (always visible when images loaded)
            if !appState.images.isEmpty {
                FileSizeEstimateView()
                    .frame(maxWidth: .infinity)

                Divider()
            }
        }
    }
}
