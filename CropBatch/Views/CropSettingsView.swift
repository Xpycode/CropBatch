import SwiftUI

struct CropSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        VStack(alignment: .leading, spacing: 12) {
            CropEdgeField(
                edge: .top,
                value: $state.cropSettings.cropTop
            )

            CropEdgeField(
                edge: .bottom,
                value: $state.cropSettings.cropBottom
            )

            CropEdgeField(
                edge: .left,
                value: $state.cropSettings.cropLeft
            )

            CropEdgeField(
                edge: .right,
                value: $state.cropSettings.cropRight
            )

            if appState.cropSettings.hasAnyCrop, let firstImage = appState.images.first {
                Divider()
                    .padding(.vertical, 4)

                let newSize = appState.cropSettings.croppedSize(from: firstImage.originalSize)
                HStack {
                    Text("Result size:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(newSize.width)) × \(Int(newSize.height))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button("Reset All") {
                appState.cropSettings = CropSettings()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .font(.caption)
            .disabled(!appState.cropSettings.hasAnyCrop)
        }
    }
}

struct CropEdgeField: View {
    let edge: CropEdge
    @Binding var value: Int

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
