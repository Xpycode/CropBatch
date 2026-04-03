import SwiftUI

// MARK: - Save in Place Section

struct SaveInPlaceSection: View {
    @Environment(AppState.self) private var appState

    private var isEnabled: Bool {
        appState.exportSettings.outputDirectory.isOverwriteMode
    }

    private var validationError: String? {
        appState.exportSettings.validateOverwriteMode(
            cornerRadiusEnabled: appState.cropSettings.cornerRadiusEnabled,
            items: appState.images
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { isEnabled },
                set: { newValue in
                    if newValue {
                        appState.exportSettings.outputDirectory = .overwriteOriginal
                    } else {
                        appState.exportSettings.outputDirectory = .sameAsSource
                    }
                    appState.markCustomSettings()
                }
            )) {
                Text("Save in place")
            }

            if isEnabled {
                if let error = validationError {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .foregroundStyle(.orange)
                    }
                    .font(.caption)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text("Originals will be replaced!")
                            .foregroundStyle(.red)
                    }
                    .font(.caption)
                }
            }
        }
    }
}
