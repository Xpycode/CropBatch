import SwiftUI

// MARK: - Crop Section (Primary)

struct CropSectionView: View {
    @Environment(AppState.self) private var appState
    @State private var presetManager = PresetManager.shared

    var body: some View {
        @Bindable var state = appState

        VStack(alignment: .leading, spacing: 12) {
            // Tool selector (centered)
            HStack(spacing: 0) {
                ForEach(EditorTool.allCases) { tool in
                    Button {
                        appState.currentTool = tool
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: tool.icon)
                            Text(tool.rawValue)
                        }
                        .font(.system(size: 12, weight: appState.currentTool == tool ? .semibold : .regular))
                        .foregroundStyle(appState.currentTool == tool ? .primary : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            appState.currentTool == tool
                                ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.15))
                                : nil
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)

            // Tool-specific controls
            if appState.currentTool == .crop {
                // MARK: Crop Tool Controls

                // TODO: [SHELVED] Preset picker - simplified UI for now
                #if false
                HStack {
                    Menu {
                        Button {
                            appState.cropSettings = CropSettings()
                            appState.recordCropChange()
                        } label: {
                            Label("None (Reset)", systemImage: "xmark")
                        }

                        Divider()

                        // Group by category
                        ForEach(PresetCategory.allCases) { category in
                            let categoryPresets = presetManager.allPresets.filter { $0.category == category }
                            if !categoryPresets.isEmpty {
                                Menu {
                                    ForEach(categoryPresets) { preset in
                                        Button {
                                            appState.applyCropPreset(preset)
                                        } label: {
                                            Text("\(preset.name) \(presetValues(preset))")
                                        }
                                    }
                                } label: {
                                    Label(category.rawValue, systemImage: category.icon)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "square.stack")
                                .foregroundStyle(.secondary)
                            Text("Preset")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                    }
                    .buttonStyle(.plain)

                    // Link mode button - shelved (not working reliably)
                }
                #endif

                // Crop edge inputs - centered
                HStack(spacing: 8) {
                    CompactCropField(label: "T", value: $state.cropSettings.cropTop) {
                        appState.recordCropChange()
                    }
                    CompactCropField(label: "B", value: $state.cropSettings.cropBottom) {
                        appState.recordCropChange()
                    }
                    CompactCropField(label: "L", value: $state.cropSettings.cropLeft) {
                        appState.recordCropChange()
                    }
                    CompactCropField(label: "R", value: $state.cropSettings.cropRight) {
                        appState.recordCropChange()
                    }
                }
                .frame(maxWidth: .infinity)

                // Reset button - centered below
                Button {
                    appState.cropSettings = CropSettings()
                    appState.recordCropChange()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset Crop")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(!appState.cropSettings.hasAnyCrop)
                .help("Reset crop")
                .frame(maxWidth: .infinity)

                Divider()

                // Snap to edges toggle
                HStack(spacing: 6) {
                    Toggle(isOn: $state.snapEnabled) {
                        Label("Snap to Edges", systemImage: "magnet")
                            .font(.caption)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                    if appState.isDetectingSnapPoints {
                        ProgressView()
                            .controlSize(.mini)
                    } else if appState.snapEnabled && appState.activeSnapPoints.hasDetections {
                        Text("\(appState.activeSnapPoints.horizontalEdges.count + appState.activeSnapPoints.verticalEdges.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.2)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)

                // Snap options (only show when snap is enabled)
                if appState.snapEnabled {
                    VStack(spacing: 6) {
                        // Threshold slider
                        HStack(spacing: 4) {
                            Text("Threshold")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Slider(value: Binding(
                                get: { Double(appState.snapThreshold) },
                                set: { appState.snapThreshold = Int($0) }
                            ), in: 5...30, step: 1)
                            .controlSize(.mini)
                            Text("\(appState.snapThreshold)px")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 30)
                        }

                        // Option toggles in a compact grid
                        HStack(spacing: 12) {
                            Toggle(isOn: $state.snapToCenter) {
                                Text("Center")
                                    .font(.caption2)
                            }
                            .toggleStyle(.checkbox)
                            .controlSize(.mini)
                            .help("Also snap to image center lines")

                            Toggle(isOn: $state.showSnapDebug) {
                                Text("Debug")
                                    .font(.caption2)
                            }
                            .toggleStyle(.checkbox)
                            .controlSize(.mini)
                            .help("Show all detected edges")
                        }
                        Text("Hold ⌥ to bypass snap")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 2)
                }

                // Aspect guide options (always visible)
                Divider()
                AdvancedCropOptionsView()

            } else if appState.currentTool == .blur {
                // MARK: Blur Tool Controls
                BlurToolSettingsPanel()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func presetValues(_ preset: CropPreset) -> String {
        let s = preset.cropSettings
        var parts: [String] = []
        if s.cropTop > 0 { parts.append("T:\(s.cropTop)") }
        if s.cropBottom > 0 { parts.append("B:\(s.cropBottom)") }
        if s.cropLeft > 0 { parts.append("L:\(s.cropLeft)") }
        if s.cropRight > 0 { parts.append("R:\(s.cropRight)") }
        return parts.isEmpty ? "" : "(\(parts.joined(separator: ", ")))"
    }
}
