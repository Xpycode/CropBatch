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

            // Suffix field
            SuffixField(suffix: Binding(
                get: { appState.exportSettings.suffix },
                set: {
                    appState.exportSettings.suffix = $0
                    appState.markCustomSettings()
                }
            ))

            // Preserve original format toggle
            Toggle("Keep original format", isOn: Binding(
                get: { appState.exportSettings.preserveOriginalFormat },
                set: {
                    appState.exportSettings.preserveOriginalFormat = $0
                    appState.markCustomSettings()
                }
            ))
            .font(.callout)

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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Preset")
                .font(.caption)
                .foregroundStyle(.secondary)

            Menu {
                ForEach(ExportPreset.presets) { preset in
                    Button {
                        appState.applyPreset(preset)
                    } label: {
                        Label(preset.name, systemImage: preset.icon)
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

// MARK: - Suffix Field

struct SuffixField: View {
    @Binding var suffix: String

    var body: some View {
        HStack {
            Text("Suffix")
                .font(.callout)

            Spacer()

            TextField("_cropped", text: $suffix)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
                .multilineTextAlignment(.trailing)
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
        VStack(alignment: .leading, spacing: 6) {
            Text("Estimated size")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                // Percentage badge
                Text("\(Int(estimate.percentage))%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(percentageColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(percentageColor.opacity(0.15))
                    )

                Text("of original")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Size breakdown
            HStack(spacing: 0) {
                Text(estimate.estimatedTotal.formattedFileSize)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)

                Text(" from ")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(estimate.originalTotal.formattedFileSize)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            // Savings indicator
            if estimate.savings > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)

                    Text("Save ~\(estimate.savings.formattedFileSize)")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            } else if estimate.savings < 0 {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)

                    Text("Increase ~\((-estimate.savings).formattedFileSize)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
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
