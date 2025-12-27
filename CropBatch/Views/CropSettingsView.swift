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
