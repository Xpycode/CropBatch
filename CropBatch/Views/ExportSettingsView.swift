import SwiftUI

struct ExportSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        VStack(alignment: .leading, spacing: 12) {
            // Preset picker
            PresetPicker()

            Divider()

            // Format picker (only if not preserving original)
            if !appState.exportSettings.preserveOriginalFormat {
                FormatPicker(format: Binding(
                    get: { appState.exportSettings.format },
                    set: {
                        appState.exportSettings.format = $0
                        appState.markCustomSettings()
                    }
                ))
            }

            // Quality slider (only for JPEG/HEIC)
            if appState.exportSettings.format.supportsCompression && !appState.exportSettings.preserveOriginalFormat {
                QualitySlider(quality: Binding(
                    get: { appState.exportSettings.quality },
                    set: {
                        appState.exportSettings.quality = $0
                        appState.markCustomSettings()
                    }
                ))
            }

            // Rename settings
            RenameSettingsSection()

            // Preserve original format toggle
            Toggle("Keep original format", isOn: Binding(
                get: { appState.exportSettings.preserveOriginalFormat },
                set: {
                    appState.exportSettings.preserveOriginalFormat = $0
                    appState.markCustomSettings()
                }
            ))
            .font(.callout)

            Divider()

            // Resize settings
            ResizeSettingsSection()

            // Output preview
            if let firstImage = appState.images.first {
                OutputPreview(inputURL: firstImage.url, exportSettings: appState.exportSettings)
            }

            // File size estimate
            if !appState.images.isEmpty && appState.cropSettings.hasAnyCrop {
                FileSizeEstimateView()
            }
        }
    }
}

// MARK: - Preset Picker

struct PresetPicker: View {
    @Environment(AppState.self) private var appState
    @State private var profileManager = ExportProfileManager.shared
    @State private var showSaveSheet = false
    @State private var newProfileName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Preset")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    newProfileName = "My Profile"
                    showSaveSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("Save current settings as profile")
            }

            Menu {
                // Built-in presets
                Section("Built-in") {
                    ForEach(ExportPreset.presets) { preset in
                        Button {
                            appState.applyPreset(preset)
                        } label: {
                            Label(preset.name, systemImage: preset.icon)
                        }
                    }
                }

                // User profiles (if any)
                if !profileManager.userProfiles.isEmpty {
                    Divider()

                    Section("My Profiles") {
                        ForEach(profileManager.userProfiles) { profile in
                            Button {
                                appState.exportSettings = profile.exportSettings
                                appState.selectedPresetID = nil
                            } label: {
                                Label(profile.name, systemImage: "person.crop.circle")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    if let preset = appState.selectedPreset {
                        Label(preset.name, systemImage: preset.icon)
                    } else {
                        Label("Custom", systemImage: "slider.horizontal.3")
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showSaveSheet) {
            SaveExportProfileSheet(profileName: $newProfileName) {
                showSaveSheet = false
            }
        }
    }
}

// MARK: - Save Export Profile Sheet

struct SaveExportProfileSheet: View {
    @Environment(AppState.self) private var appState
    @Binding var profileName: String
    let onDismiss: () -> Void
    @State private var profileManager = ExportProfileManager.shared

    var body: some View {
        VStack(spacing: 16) {
            Text("Save Export Profile")
                .font(.headline)

            TextField("Profile name", text: $profileName)
                .textFieldStyle(.roundedBorder)

            // Settings preview
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Format:")
                        .foregroundStyle(.secondary)
                    Text(appState.exportSettings.preserveOriginalFormat ? "Original" : appState.exportSettings.format.rawValue)
                }
                .font(.caption)

                if appState.exportSettings.format.supportsCompression && !appState.exportSettings.preserveOriginalFormat {
                    HStack {
                        Text("Quality:")
                            .foregroundStyle(.secondary)
                        Text("\(Int(appState.exportSettings.quality * 100))%")
                    }
                    .font(.caption)
                }

                HStack {
                    Text("Suffix:")
                        .foregroundStyle(.secondary)
                    Text(appState.exportSettings.suffix.isEmpty ? "(none)" : appState.exportSettings.suffix)
                        .fontDesign(.monospaced)
                }
                .font(.caption)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))

            HStack {
                Button("Cancel", role: .cancel) {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    profileManager.saveProfile(name: profileName, settings: appState.exportSettings)
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(profileName.isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
    }
}

// MARK: - Format Picker

struct FormatPicker: View {
    @Binding var format: ExportFormat

    var body: some View {
        HStack {
            Text("Format")
                .font(.callout)

            Spacer()

            Picker("", selection: $format) {
                ForEach(ExportFormat.allCases) { fmt in
                    Text(fmt.rawValue).tag(fmt)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 100)
        }
    }
}

// MARK: - Quality Slider

struct QualitySlider: View {
    @Binding var quality: Double

    private var qualityPercent: Int {
        Int(quality * 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Quality")
                    .font(.callout)
                Spacer()
                Text("\(qualityPercent)%")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Slider(value: $quality, in: 0.1...1.0, step: 0.05)
                .controlSize(.small)
        }
    }
}

// MARK: - Output Preview

struct OutputPreview: View {
    let inputURL: URL
    let exportSettings: ExportSettings

    private var outputFilename: String {
        exportSettings.outputURL(for: inputURL).lastPathComponent
    }

    private var wouldOverwrite: Bool {
        exportSettings.wouldOverwriteOriginal(for: inputURL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Output preview")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                if wouldOverwrite {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Text(outputFilename)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(wouldOverwrite ? .red : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if wouldOverwrite {
                Text("Would overwrite original!")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

// MARK: - Resize Settings Section

struct ResizeSettingsSection: View {
    @Environment(AppState.self) private var appState

    // Short labels for resize mode buttons
    private func shortLabel(for mode: ResizeMode) -> String {
        switch mode {
        case .none: return "None"
        case .exactSize: return "Exact"
        case .maxWidth: return "MaxW"
        case .maxHeight: return "MaxH"
        case .percentage: return "%"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Resize mode buttons
            VStack(spacing: 4) {
                Text("Resize")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    ForEach(ResizeMode.allCases) { mode in
                        Button {
                            appState.exportSettings.resizeSettings.mode = mode
                            appState.markCustomSettings()
                        } label: {
                            Text(shortLabel(for: mode))
                                .font(.system(size: 10, weight: .medium))
                                .frame(minWidth: 32, minHeight: 22)
                        }
                        .buttonStyle(.bordered)
                        .tint(appState.exportSettings.resizeSettings.mode == mode ? .accentColor : .secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            if appState.exportSettings.resizeSettings.mode != .none {
                resizeControls
            }
        }
    }

    @ViewBuilder
    private var resizeControls: some View {
        let mode = appState.exportSettings.resizeSettings.mode

        switch mode {
        case .none:
            EmptyView()

        case .exactSize:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Width")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Width", value: Binding(
                            get: { appState.exportSettings.resizeSettings.width },
                            set: {
                                appState.exportSettings.resizeSettings.width = max(1, $0)
                                appState.markCustomSettings()
                            }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    }

                    Text("×")
                        .foregroundStyle(.secondary)
                        .padding(.top, 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Height")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Height", value: Binding(
                            get: { appState.exportSettings.resizeSettings.height },
                            set: {
                                appState.exportSettings.resizeSettings.height = max(1, $0)
                                appState.markCustomSettings()
                            }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    }

                    Spacer()
                }

                Toggle("Maintain aspect ratio", isOn: Binding(
                    get: { appState.exportSettings.resizeSettings.maintainAspectRatio },
                    set: {
                        appState.exportSettings.resizeSettings.maintainAspectRatio = $0
                        appState.markCustomSettings()
                    }
                ))
                .font(.caption)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))

        case .maxWidth:
            HStack {
                Text("Max width")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                TextField("Width", value: Binding(
                    get: { appState.exportSettings.resizeSettings.width },
                    set: {
                        appState.exportSettings.resizeSettings.width = max(1, $0)
                        appState.markCustomSettings()
                    }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)

                Text("px")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .maxHeight:
            HStack {
                Text("Max height")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                TextField("Height", value: Binding(
                    get: { appState.exportSettings.resizeSettings.height },
                    set: {
                        appState.exportSettings.resizeSettings.height = max(1, $0)
                        appState.markCustomSettings()
                    }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)

                Text("px")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .percentage:
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Scale")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(appState.exportSettings.resizeSettings.percentage))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(value: Binding(
                    get: { appState.exportSettings.resizeSettings.percentage },
                    set: {
                        appState.exportSettings.resizeSettings.percentage = $0
                        appState.markCustomSettings()
                    }
                ), in: 10...200, step: 5)
                .controlSize(.small)
            }
        }
    }
}

// MARK: - Rename Settings Section

struct RenameSettingsSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Naming")
                    .font(.callout)

                Spacer()

                Picker("", selection: Binding(
                    get: { appState.exportSettings.renameSettings.mode },
                    set: {
                        appState.exportSettings.renameSettings.mode = $0
                        appState.markCustomSettings()
                    }
                )) {
                    ForEach(RenameMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }

            // Show suffix field for keep original mode, pattern field for pattern mode
            if appState.exportSettings.renameSettings.mode == .keepOriginal {
                HStack {
                    Text("Suffix")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    TextField("_cropped", text: Binding(
                        get: { appState.exportSettings.suffix },
                        set: {
                            appState.exportSettings.suffix = $0
                            appState.markCustomSettings()
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .multilineTextAlignment(.trailing)
                }
            } else {
                patternEditor
            }
        }
    }

    @ViewBuilder
    private var patternEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Pattern field
            HStack {
                Text("Pattern")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                TextField("{name}_{counter}", text: Binding(
                    get: { appState.exportSettings.renameSettings.pattern },
                    set: {
                        appState.exportSettings.renameSettings.pattern = $0
                        appState.markCustomSettings()
                    }
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

            // Counter settings
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("Start:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("1", value: Binding(
                        get: { appState.exportSettings.renameSettings.startIndex },
                        set: {
                            appState.exportSettings.renameSettings.startIndex = max(0, $0)
                            appState.markCustomSettings()
                        }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                }

                HStack(spacing: 4) {
                    Text("Digits:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("", selection: Binding(
                        get: { appState.exportSettings.renameSettings.zeroPadding },
                        set: {
                            appState.exportSettings.renameSettings.zeroPadding = $0
                            appState.markCustomSettings()
                        }
                    )) {
                        Text("1").tag(1)
                        Text("2").tag(2)
                        Text("3").tag(3)
                        Text("4").tag(4)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 55)
                }
            }

            // Preview
            if let firstImage = appState.images.first {
                let preview = appState.exportSettings.renameSettings.preview(
                    originalName: firstImage.url.deletingPathExtension().lastPathComponent,
                    index: 0
                )
                HStack(spacing: 4) {
                    Text("Preview:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(preview)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

// MARK: - File Size Estimate

struct FileSizeEstimateView: View {
    @Environment(AppState.self) private var appState

    private var estimate: FileSizeEstimate {
        FileSizeEstimator.estimate(
            images: appState.images,
            cropSettings: appState.cropSettings,
            exportSettings: appState.exportSettings
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            // Percentage badge
            Text("\(Int(estimate.percentage))%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(percentageColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(percentageColor.opacity(0.15)))

            // Size: estimated from original
            Text("\(estimate.estimatedTotal.formattedFileSize) from \(estimate.originalTotal.formattedFileSize)")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer()

            // Savings indicator
            if estimate.savings > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text("−\(estimate.savings.formattedFileSize)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.green)
                }
            } else if estimate.savings < 0 {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text("+\((-estimate.savings).formattedFileSize)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private var percentageColor: Color {
        if estimate.percentage < 50 {
            return .green
        } else if estimate.percentage < 100 {
            return .blue
        } else {
            return .orange
        }
    }
}

#Preview {
    ExportSettingsView()
        .environment(AppState())
        .frame(width: 250)
        .padding()
}
