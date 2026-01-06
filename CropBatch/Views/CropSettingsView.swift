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

            // Snap to edges toggle
            HStack(spacing: 8) {
                Toggle(isOn: $state.snapEnabled) {
                    Label("Snap to Edges", systemImage: "rectangle.on.rectangle.angled")
                        .font(.caption)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)

                if appState.isDetectingSnapPoints {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .help("Snap crop handles to detected UI element edges (S to toggle)")

            // Corner Radius section
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $state.cropSettings.cornerRadiusEnabled) {
                    Text("Corner Radius")
                        .font(.callout)
                }
                .toggleStyle(.checkbox)

                if appState.cropSettings.cornerRadiusEnabled {
                    HStack(spacing: 8) {
                        TextField("10", value: $state.cropSettings.cornerRadius, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)

                        Text("px")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()
                    }
                    .padding(.leading, 20)

                    Toggle(isOn: $state.cropSettings.independentCorners) {
                        Text("Independent corners")
                            .font(.caption)
                    }
                    .toggleStyle(.checkbox)
                    .padding(.leading, 20)

                    if appState.cropSettings.independentCorners {
                        VStack(spacing: 4) {
                            HStack(spacing: 8) {
                                Text("TL")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                TextField("10", value: $state.cropSettings.cornerRadiusTL, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 50)
                                    .multilineTextAlignment(.trailing)

                                Text("TR")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                TextField("10", value: $state.cropSettings.cornerRadiusTR, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 50)
                                    .multilineTextAlignment(.trailing)
                            }
                            HStack(spacing: 8) {
                                Text("BL")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                TextField("10", value: $state.cropSettings.cornerRadiusBL, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 50)
                                    .multilineTextAlignment(.trailing)

                                Text("BR")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                TextField("10", value: $state.cropSettings.cornerRadiusBR, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 50)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        .padding(.leading, 20)
                    }

                    Text("Output will be PNG (transparency)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                }
            }

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

                // Snap point count indicator
                if appState.snapEnabled && appState.activeSnapPoints.hasDetections {
                    Text("\(appState.activeSnapPoints.horizontalEdges.count + appState.activeSnapPoints.verticalEdges.count) edges")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
    
    @State private var isDragging = false
    @State private var isHovering = false
    @State private var dragStartValue: Int = 0
    
    // Sensitivity: points of drag per 1px value change
    private let dragSensitivity: CGFloat = 2.0

    var body: some View {
        HStack(spacing: 6) {
            // Dedicated drag handle area
            dragHandle
            
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
    
    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(isDragging ? Color.accentColor.opacity(0.3) : (isHovering ? Color.secondary.opacity(0.2) : Color.secondary.opacity(0.1)))
            .frame(width: 20, height: 24)
            .overlay {
                VStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 0.5)
                            .fill(isDragging ? Color.accentColor : (isHovering ? Color.secondary : Color.secondary.opacity(0.5)))
                            .frame(width: 10, height: 1.5)
                    }
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else if !isDragging {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            dragStartValue = value
                            NSCursor.resizeLeftRight.push()
                        }
                        let delta = Int(gesture.translation.width / dragSensitivity)
                        let newValue = max(0, dragStartValue + delta)
                        value = newValue
                    }
                    .onEnded { _ in
                        isDragging = false
                        NSCursor.pop()
                        onCommit?()
                    }
            )
            .accessibilityLabel("\(edge.rawValue) crop drag handle")
            .accessibilityValue("\(value) pixels")
            .accessibilityHint("Drag left or right to adjust \(edge.rawValue) crop value")
            .accessibilityAddTraits(.allowsDirectInteraction)
    }
}

#Preview {
    CropSettingsView()
        .environment(AppState())
        .frame(width: 250)
        .padding()
}
