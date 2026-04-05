import SwiftUI

// MARK: - Snap Options (Content only, toggle in header)

struct SnapOptionsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        LabeledContent("Threshold") {
            HStack(spacing: 8) {
                Slider(value: Binding(
                    get: { Double(appState.snapThreshold) },
                    set: { appState.snapThreshold = Int($0) }
                ), in: 5...30, step: 1)
                .frame(maxWidth: 100)
                Text("\(appState.snapThreshold)px")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
            }
        }

        LabeledContent("Edge Sensitivity") {
            HStack(spacing: 8) {
                Slider(value: $state.edgeSensitivity, in: 0.0...1.0) { isEditing in
                    if !isEditing {
                        appState.applyEdgeSensitivity()
                    }
                }
                .frame(maxWidth: 100)
                Text(sensitivityLabel)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
        }

        Toggle("Snap to Center", isOn: $state.snapToCenter)
            .help("Also snap to image center lines")

        Toggle("Show Debug", isOn: $state.showSnapDebug)
            .help("Show all detected edges")

        Text("Hold ⌥ to bypass snap")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }

    private var sensitivityLabel: String {
        if appState.edgeSensitivity < 0.33 { return "Low" }
        if appState.edgeSensitivity < 0.66 { return "Med" }
        return "High"
    }
}
