import SwiftUI

struct CropSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var detectionResult: UIDetectionResult?
    @State private var isDetecting = false

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

            // Auto-detect button
            if !appState.images.isEmpty {
                Divider()

                AutoDetectView(
                    detectionResult: $detectionResult,
                    isDetecting: $isDetecting
                )
            }

            HStack {
                Button("Reset All") {
                    appState.cropSettings = CropSettings()
                    detectionResult = nil
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

// MARK: - Auto Detect View

struct AutoDetectView: View {
    @Environment(AppState.self) private var appState
    @Binding var detectionResult: UIDetectionResult?
    @Binding var isDetecting: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Detect button
            Button {
                runDetection()
            } label: {
                HStack {
                    if isDetecting {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "wand.and.stars")
                    }
                    Text("Auto-Detect UI")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isDetecting || appState.images.isEmpty)

            // Detection results
            if let result = detectionResult, result.hasDetection {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Detected:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if result.suggestedTop > 0 {
                        DetectionResultRow(
                            edge: "Top",
                            pixels: result.suggestedTop,
                            description: result.topDescription
                        ) {
                            appState.cropSettings.cropTop = result.suggestedTop
                        }
                    }

                    if result.suggestedBottom > 0 {
                        DetectionResultRow(
                            edge: "Bottom",
                            pixels: result.suggestedBottom,
                            description: result.bottomDescription
                        ) {
                            appState.cropSettings.cropBottom = result.suggestedBottom
                        }
                    }

                    // Apply all button
                    Button("Apply All Detected") {
                        appState.cropSettings = result.asCropSettings
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.green.opacity(0.1)))
            } else if detectionResult != nil {
                Text("No UI elements detected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
        }
    }

    private func runDetection() {
        isDetecting = true

        Task {
            // Use batch detection if multiple images, otherwise single image
            let result: UIDetectionResult
            if appState.images.count > 1 {
                result = UIDetector.detectCommon(in: appState.images)
            } else if let image = appState.activeImage {
                result = UIDetector.detect(in: image.originalImage)
            } else {
                result = UIDetectionResult()
            }

            await MainActor.run {
                detectionResult = result
                isDetecting = false
            }
        }
    }
}

struct DetectionResultRow: View {
    let edge: String
    let pixels: Int
    let description: String?
    let onApply: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(edge)
                        .font(.caption.weight(.medium))
                    Text("\(pixels)px")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if let description = description {
                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }

            Spacer()

            Button("Apply") {
                onApply()
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
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
