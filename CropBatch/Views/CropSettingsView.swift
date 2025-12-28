import SwiftUI

struct CropSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var detectionResult: UIDetectionResult?
    @State private var isDetecting = false

    var body: some View {
        @Bindable var state = appState

        VStack(alignment: .leading, spacing: 12) {
            CropEdgeField(edge: .top, value: $state.cropSettings.cropTop) {
                appState.recordCropChange()
            }
            .onChange(of: appState.cropSettings.cropTop) { _, newValue in
                applyLinkedChange(edge: .top, value: newValue)
            }

            CropEdgeField(edge: .bottom, value: $state.cropSettings.cropBottom) {
                appState.recordCropChange()
            }
            .onChange(of: appState.cropSettings.cropBottom) { _, newValue in
                applyLinkedChange(edge: .bottom, value: newValue)
            }

            CropEdgeField(edge: .left, value: $state.cropSettings.cropLeft) {
                appState.recordCropChange()
            }
            .onChange(of: appState.cropSettings.cropLeft) { _, newValue in
                applyLinkedChange(edge: .left, value: newValue)
            }

            CropEdgeField(edge: .right, value: $state.cropSettings.cropRight) {
                appState.recordCropChange()
            }
            .onChange(of: appState.cropSettings.cropRight) { _, newValue in
                applyLinkedChange(edge: .right, value: newValue)
            }

            // Edge linking - compact button group
            VStack(alignment: .leading, spacing: 4) {
                Text("Link Edges")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    ForEach(EdgeLinkMode.allCases) { mode in
                        Button {
                            appState.edgeLinkMode = mode
                        } label: {
                            Image(systemName: mode.icon)
                                .font(.caption)
                                .frame(width: 28, height: 22)
                        }
                        .buttonStyle(.bordered)
                        .tint(appState.edgeLinkMode == mode ? .accentColor : .secondary)
                        .help(mode.rawValue)
                    }
                }
            }

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
                    appState.recordCropChange()
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

    @State private var isApplyingLinked = false

    private func applyLinkedChange(edge: CropEdge, value: Int) {
        guard !isApplyingLinked else { return }
        isApplyingLinked = true

        switch appState.edgeLinkMode {
        case .none:
            break
        case .vertical:
            if edge == .top {
                appState.cropSettings.cropBottom = value
            } else if edge == .bottom {
                appState.cropSettings.cropTop = value
            }
        case .horizontal:
            if edge == .left {
                appState.cropSettings.cropRight = value
            } else if edge == .right {
                appState.cropSettings.cropLeft = value
            }
        case .all:
            appState.cropSettings.setAllEdges(value)
        }

        // Validate and clamp all crop values to prevent exceeding image dimensions
        appState.validateAndClampCrop()

        isApplyingLinked = false
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
                            appState.recordCropChange()
                        }
                    }

                    if result.suggestedBottom > 0 {
                        DetectionResultRow(
                            edge: "Bottom",
                            pixels: result.suggestedBottom,
                            description: result.bottomDescription
                        ) {
                            appState.cropSettings.cropBottom = result.suggestedBottom
                            appState.recordCropChange()
                        }
                    }

                    // Apply all button
                    Button("Apply All Detected") {
                        appState.cropSettings = result.asCropSettings
                        appState.recordCropChange()
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
