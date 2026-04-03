import SwiftUI

// MARK: - Crop Controls (Always Visible)

struct CropControlsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        // Crop edge inputs - horizontal row
        LabeledContent("Crop") {
            HStack(spacing: 6) {
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
        }
        .controlSize(.small)

        // Reset button
        Button {
            appState.cropSettings = CropSettings()
            appState.recordCropChange()
        } label: {
            Label("Reset Crop", systemImage: "arrow.counterclockwise")
        }
        .controlSize(.small)
        .disabled(!appState.cropSettings.hasAnyCrop)
        .help("Reset crop to zero")

        // Corner Radius
        LabeledContent("Corner Radius") {
            Toggle("", isOn: $state.cropSettings.cornerRadiusEnabled)
                .labelsHidden()
                .controlSize(.small)
        }

        if appState.cropSettings.cornerRadiusEnabled {
            // Radius controls - same structure as crop section
            LabeledContent {
                HStack(spacing: 6) {
                    if appState.cropSettings.independentCorners {
                        CompactCropField(label: "TL", value: $state.cropSettings.cornerRadiusTL)
                        CompactCropField(label: "TR", value: $state.cropSettings.cornerRadiusTR)
                        CompactCropField(label: "BL", value: $state.cropSettings.cornerRadiusBL)
                        CompactCropField(label: "BR", value: $state.cropSettings.cornerRadiusBR)
                    } else {
                        CompactCropField(label: "R", value: $state.cropSettings.cornerRadius)
                    }
                }
            } label: {
                Toggle("Per-corner", isOn: $state.cropSettings.independentCorners)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
            }

            Text("Exports as PNG for transparency")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
