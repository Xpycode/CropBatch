import SwiftUI

/// Blur tool overlay for drawing blur regions
struct BlurToolOverlay: View {
    @Environment(AppState.self) private var appState
    let imageSize: CGSize
    let displayedSize: CGSize

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?

    private var scale: CGFloat {
        displayedSize.width / imageSize.width
    }

    var body: some View {
        GeometryReader { geometry in
            let offsetX = (geometry.size.width - displayedSize.width) / 2
            let offsetY = (geometry.size.height - displayedSize.height) / 2

            ZStack {
                // Existing blur regions
                ForEach(appState.activeImageBlurRegions) { region in
                    BlurRegionView(
                        region: region,
                        scale: scale,
                        offset: CGPoint(x: offsetX, y: offsetY),
                        onDelete: {
                            appState.removeBlurRegion(region.id)
                        }
                    )
                }

                // Current drag region preview
                if let start = dragStart, let current = dragCurrent {
                    let rect = normalizedRect(from: start, to: current)
                    Rectangle()
                        .fill(previewColor.opacity(0.3))
                        .overlay(
                            Rectangle()
                                .strokeBorder(previewColor, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                        )
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }

                // Drawing area (invisible, captures gestures)
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 5)
                            .onChanged { value in
                                // Check if within image bounds
                                let location = value.location
                                let imageRect = CGRect(
                                    x: offsetX,
                                    y: offsetY,
                                    width: displayedSize.width,
                                    height: displayedSize.height
                                )

                                if dragStart == nil && imageRect.contains(value.startLocation) {
                                    dragStart = value.startLocation
                                }

                                if dragStart != nil {
                                    // Clamp to image bounds
                                    dragCurrent = CGPoint(
                                        x: min(max(location.x, offsetX), offsetX + displayedSize.width),
                                        y: min(max(location.y, offsetY), offsetY + displayedSize.height)
                                    )
                                }
                            }
                            .onEnded { _ in
                                if let start = dragStart, let current = dragCurrent {
                                    let screenRect = normalizedRect(from: start, to: current)

                                    // Convert to image coordinates
                                    let imageRect = CGRect(
                                        x: (screenRect.minX - offsetX) / scale,
                                        y: (screenRect.minY - offsetY) / scale,
                                        width: screenRect.width / scale,
                                        height: screenRect.height / scale
                                    )

                                    // Only add if region is large enough (at least 10x10 pixels)
                                    if imageRect.width >= 10 && imageRect.height >= 10 {
                                        let region = BlurRegion(
                                            rect: imageRect,
                                            style: appState.blurStyle
                                        )
                                        appState.addBlurRegion(region)
                                    }
                                }

                                dragStart = nil
                                dragCurrent = nil
                            }
                    )
            }
        }
    }

    private var previewColor: Color {
        switch appState.blurStyle {
        case .blur: return .blue
        case .pixelate: return .purple
        case .solidBlack: return .black
        case .solidWhite: return .gray
        }
    }

    private func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
}

/// Individual blur region visualization
struct BlurRegionView: View {
    let region: BlurRegion
    let scale: CGFloat
    let offset: CGPoint
    let onDelete: () -> Void

    @State private var isHovering = false

    private var displayRect: CGRect {
        CGRect(
            x: offset.x + region.rect.origin.x * scale,
            y: offset.y + region.rect.origin.y * scale,
            width: region.rect.width * scale,
            height: region.rect.height * scale
        )
    }

    private var styleColor: Color {
        switch region.style {
        case .blur: return .blue
        case .pixelate: return .purple
        case .solidBlack: return .black
        case .solidWhite: return .gray
        }
    }

    var body: some View {
        ZStack {
            // Region rectangle
            Rectangle()
                .fill(styleColor.opacity(0.25))
                .overlay(
                    Rectangle()
                        .strokeBorder(styleColor, lineWidth: isHovering ? 3 : 2)
                )
                .frame(width: displayRect.width, height: displayRect.height)
                .position(x: displayRect.midX, y: displayRect.midY)

            // Delete button on hover
            if isHovering {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white, .red)
                        .shadow(radius: 2)
                }
                .buttonStyle(.plain)
                .position(x: displayRect.maxX - 10, y: displayRect.minY + 10)
            }

            // Style label
            Text(region.style.rawValue)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(styleColor))
                .position(x: displayRect.midX, y: displayRect.maxY - 12)
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

/// Blur tool settings panel (for sidebar)
struct BlurToolSettings: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        VStack(alignment: .leading, spacing: 12) {
            // Tool selector
            HStack {
                Text("Tool")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Picker("", selection: $state.currentTool) {
                    ForEach(EditorTool.allCases) { tool in
                        Label(tool.rawValue, systemImage: tool.icon).tag(tool)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }

            if appState.currentTool == .blur {
                Divider()

                // Blur style picker
                HStack {
                    Text("Style")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Picker("", selection: $state.blurStyle) {
                        ForEach(BlurRegion.BlurStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }

                // Instructions
                VStack(alignment: .leading, spacing: 4) {
                    Text("Draw rectangles on the image to blur or redact areas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Hover over a region and click X to remove it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)

                // Blur regions count
                if !appState.activeImageBlurRegions.isEmpty {
                    HStack {
                        Text("\(appState.activeImageBlurRegions.count) region(s)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Clear All") {
                            appState.clearBlurRegions()
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}

#Preview {
    BlurToolSettings()
        .environment(AppState())
        .frame(width: 250)
        .padding()
}
