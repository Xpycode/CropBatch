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
    }
}

#Preview {
    CropSettingsView()
        .environment(AppState())
        .frame(width: 250)
        .padding()
}
