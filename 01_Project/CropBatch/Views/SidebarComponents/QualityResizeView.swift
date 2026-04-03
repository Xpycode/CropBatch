import SwiftUI

// MARK: - Quality & Resize (Collapsible)

struct QualityResizeView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        // Quality slider (for JPEG/HEIC/WebP)
        if appState.exportSettings.format.supportsCompression {
            LabeledContent("Quality") {
                HStack(spacing: 8) {
                    Slider(value: Binding(
                        get: { appState.exportSettings.quality },
                        set: { appState.exportSettings.quality = $0; appState.markCustomSettings() }
                    ), in: 0.1...1.0, step: 0.05)
                    .frame(maxWidth: 120)
                    Text("\(Int(appState.exportSettings.quality * 100))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }

        // Suffix field (when using Keep Original naming)
        if appState.exportSettings.renameSettings.mode == .keepOriginal {
            LabeledContent("Suffix") {
                TextField("", text: Binding(
                    get: { appState.exportSettings.suffix },
                    set: { appState.exportSettings.suffix = $0; appState.markCustomSettings() }
                ), prompt: Text("_cropped"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
            }
        }

        // Pattern field (when using Pattern naming)
        if appState.exportSettings.renameSettings.mode == .pattern {
            LabeledContent("Pattern") {
                TextField("", text: Binding(
                    get: { appState.exportSettings.renameSettings.pattern },
                    set: { appState.exportSettings.renameSettings.pattern = $0; appState.markCustomSettings() }
                ), prompt: Text("{name}_{n}"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
                .font(.system(.body, design: .monospaced))
            }

            // Token buttons
            LabeledContent("Tokens") {
                HStack(spacing: 4) {
                    ForEach(RenameSettings.availableTokens, id: \.token) { token in
                        Button(token.token) {
                            appState.exportSettings.renameSettings.pattern += token.token
                            appState.markCustomSettings()
                        }
                        .help(token.description)
                    }
                }
                .controlSize(.mini)
                .buttonStyle(.bordered)
            }
        }

        // Resize settings - use LabeledContent for consistency
        LabeledContent("Resize") {
            HStack(spacing: 4) {
                ForEach(ResizeMode.allCases) { mode in
                    Button {
                        appState.exportSettings.resizeSettings.mode = mode
                        appState.markCustomSettings()
                    } label: {
                        Text(shortLabel(for: mode))
                            .frame(minWidth: 28)
                    }
                    .buttonStyle(.bordered)
                    .tint(appState.exportSettings.resizeSettings.mode == mode ? .accentColor : .secondary)
                }
            }
            .controlSize(.small)
        }

        // Resize dimension controls when not "none"
        if appState.exportSettings.resizeSettings.mode != .none {
            resizeControls
        }
    }

    private func shortLabel(for mode: ResizeMode) -> String {
        switch mode {
        case .none: return "None"
        case .exactSize: return "Exact"
        case .maxWidth: return "W"
        case .maxHeight: return "H"
        case .percentage: return "%"
        }
    }

    @ViewBuilder
    private var resizeControls: some View {
        switch appState.exportSettings.resizeSettings.mode {
        case .none:
            EmptyView()
        case .exactSize:
            LabeledContent("Size") {
                HStack(spacing: 4) {
                    TextField("W", value: Binding(
                        get: { appState.exportSettings.resizeSettings.width },
                        set: { appState.exportSettings.resizeSettings.width = $0; appState.markCustomSettings() }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    Text("×")
                        .foregroundStyle(.secondary)
                    TextField("H", value: Binding(
                        get: { appState.exportSettings.resizeSettings.height },
                        set: { appState.exportSettings.resizeSettings.height = $0; appState.markCustomSettings() }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                }
            }
        case .maxWidth:
            LabeledContent("Max Width") {
                TextField("px", value: Binding(
                    get: { appState.exportSettings.resizeSettings.width },
                    set: { appState.exportSettings.resizeSettings.width = $0; appState.markCustomSettings() }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
            }
        case .maxHeight:
            LabeledContent("Max Height") {
                TextField("px", value: Binding(
                    get: { appState.exportSettings.resizeSettings.height },
                    set: { appState.exportSettings.resizeSettings.height = $0; appState.markCustomSettings() }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
            }
        case .percentage:
            LabeledContent("Scale") {
                HStack(spacing: 4) {
                    Slider(value: Binding(
                        get: { appState.exportSettings.resizeSettings.percentage },
                        set: { appState.exportSettings.resizeSettings.percentage = $0; appState.markCustomSettings() }
                    ), in: 10...200, step: 5)
                    .frame(width: 100)
                    Text("\(Int(appState.exportSettings.resizeSettings.percentage))%")
                        .monospacedDigit()
                        .frame(width: 40)
                }
            }
        }
    }
}
