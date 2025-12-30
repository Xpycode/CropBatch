import SwiftUI

struct CropSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        VStack(alignment: .leading, spacing: 12) {
            CropEdgeField(edge: .top, value: $state.cropSettings.cropTop) {
                appState.recordCropChange()
            }

            CropEdgeField(edge: .bottom, value: $state.cropSettings.cropBottom) {
                appState.recordCropChange()
            }

            CropEdgeField(edge: .left, value: $state.cropSettings.cropLeft) {
                appState.recordCropChange()
            }

            CropEdgeField(edge: .right, value: $state.cropSettings.cropRight) {
                appState.recordCropChange()
            }

            // MARK: - Edge Linking (shelved - not working reliably)
            // TODO: Fix SwiftUI onChange timing issues with linked value updates
            // The feature is preserved in EdgeLinkMode enum and AppState.edgeLinkMode

            // Aspect ratio guide - compact button group
            VStack(alignment: .leading, spacing: 4) {
                Text("Aspect Guide")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    // None button
                    Button {
                        appState.showAspectRatioGuide = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .frame(width: 28, height: 22)
                    }
                    .buttonStyle(.bordered)
                    .tint(appState.showAspectRatioGuide == nil ? .accentColor : .secondary)
                    .help("None")

                    ForEach(AspectRatioGuide.allCases) { guide in
                        Button {
                            appState.showAspectRatioGuide = guide
                        } label: {
                            Text(guide.rawValue)
                                .font(.system(size: 9, weight: .medium))
                                .frame(minWidth: 28, minHeight: 22)
                        }
                        .buttonStyle(.bordered)
                        .tint(appState.showAspectRatioGuide == guide ? .yellow : .secondary)
                        .help(guide.description)
                    }
                }
            }

            // Auto-detect UI - shelved (not working reliably)

            HStack {
                Button("Reset All") {
                    appState.cropSettings = CropSettings()
                    appState.recordCropChange()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .font(.caption)
                .disabled(!appState.cropSettings.hasAnyCrop)

                Spacer()
            }
        }
    }

}

// MARK: - Auto Detect View (shelved - not working reliably)
// UIDetector and related code preserved in Services/UIDetector.swift

struct CropEdgeField: View {
    let edge: CropEdge
    @Binding var value: Int
    var onCommit: (() -> Void)? = nil

    var body: some View {
        HStack {
            Image(systemName: edge.systemImage)
                .frame(width: 16)
                .foregroundStyle(.secondary)

            Text(edge.rawValue)
                .font(.callout)

            Spacer()

            TextField("0", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                .multilineTextAlignment(.trailing)
                .onSubmit { onCommit?() }

            Text("px")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    CropSettingsView()
        .environment(AppState())
        .frame(width: 250)
        .padding()
}
