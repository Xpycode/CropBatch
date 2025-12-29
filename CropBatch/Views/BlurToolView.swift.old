import SwiftUI

/// Blur tool overlay for drawing and editing blur regions
struct BlurToolOverlay: View {
    @Environment(AppState.self) private var appState
    let imageSize: CGSize
    let displayedSize: CGSize
    let displayedImage: NSImage  // For live preview

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var isDraggingNewRegion = false
    @State private var isMovingRegion = false
    @State private var isResizingRegion = false
    @State private var resizeHandle: ResizeHandle?
    @State private var dragOffset: CGSize = .zero

    private var scale: CGFloat {
        displayedSize.width / imageSize.width
    }

    enum ResizeHandle {
        case topLeft, topRight, bottomLeft, bottomRight
        case top, bottom, left, right
    }

    var body: some View {
        GeometryReader { geometry in
            let offsetX = (geometry.size.width - displayedSize.width) / 2
            let offsetY = (geometry.size.height - displayedSize.height) / 2
            let imageRect = CGRect(
                x: offsetX,
                y: offsetY,
                width: displayedSize.width,
                height: displayedSize.height
            )

            ZStack {
                // Background tap area for deselection (lowest z-order)
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appState.selectBlurRegion(nil)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { value in
                                handleNewRegionDrag(value: value, imageRect: imageRect, offsetX: offsetX, offsetY: offsetY)
                            }
                            .onEnded { _ in
                                finishNewRegionDrag(offsetX: offsetX, offsetY: offsetY)
                            }
                    )

                // Current drag region preview (for new regions)
                if let start = dragStart, let current = dragCurrent, isDraggingNewRegion {
                    let rect = normalizedRect(from: start, to: current)
                    Rectangle()
                        .fill(previewColor.opacity(0.3))
                        .overlay(
                            Rectangle()
                                .strokeBorder(previewColor, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                        )
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }

                // Existing blur regions (interactive - highest z-order)
                ForEach(appState.activeImageBlurRegions) { region in
                    EditableBlurRegionView(
                        region: region,
                        scale: scale,
                        offset: CGPoint(x: offsetX, y: offsetY),
                        imageSize: imageSize,
                        displayedImage: displayedImage,
                        isSelected: appState.selectedBlurRegionID == region.id,
                        onSelect: {
                            appState.selectBlurRegion(region.id)
                        },
                        onDelete: {
                            appState.removeBlurRegion(region.id)
                        },
                        onMove: { newRect in
                            appState.updateBlurRegion(region.id, rect: newRect)
                        }
                    )
                    // Only include intensity/style in id (NOT rect - that causes jitter during drag)
                    .id("\(region.id)-\(Int(region.intensity * 100))-\(region.style.rawValue)")
                }
            }
        }
    }

    private func handleNewRegionDrag(value: DragGesture.Value, imageRect: CGRect, offsetX: CGFloat, offsetY: CGFloat) {
        // Only start new region if not clicking on existing region
        if !isDraggingNewRegion && dragStart == nil {
            // Check if starting within image bounds
            guard imageRect.contains(value.startLocation) else { return }

            // Check if we're clicking on an existing region
            let clickedOnRegion = appState.activeImageBlurRegions.contains { region in
                let displayRect = CGRect(
                    x: offsetX + region.rect.origin.x * scale,
                    y: offsetY + region.rect.origin.y * scale,
                    width: region.rect.width * scale,
                    height: region.rect.height * scale
                )
                return displayRect.contains(value.startLocation)
            }

            if !clickedOnRegion {
                appState.selectBlurRegion(nil)
                dragStart = value.startLocation
                isDraggingNewRegion = true
            }
        }

        if isDraggingNewRegion {
            dragCurrent = CGPoint(
                x: min(max(value.location.x, imageRect.minX), imageRect.maxX),
                y: min(max(value.location.y, imageRect.minY), imageRect.maxY)
            )
        }
    }

    private func finishNewRegionDrag(offsetX: CGFloat, offsetY: CGFloat) {
        defer {
            dragStart = nil
            dragCurrent = nil
            isDraggingNewRegion = false
        }

        guard isDraggingNewRegion, let start = dragStart, let current = dragCurrent else { return }

        let screenRect = normalizedRect(from: start, to: current)
        let imageRect = CGRect(
            x: (screenRect.minX - offsetX) / scale,
            y: (screenRect.minY - offsetY) / scale,
            width: screenRect.width / scale,
            height: screenRect.height / scale
        )

        guard imageRect.width >= 10 && imageRect.height >= 10 else { return }

        let region = BlurRegion(
            rect: imageRect,
            style: appState.blurStyle,
            intensity: appState.blurIntensity
        )
        appState.addBlurRegion(region)
        appState.selectBlurRegion(region.id)
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

/// Editable blur region with move/resize handles
struct EditableBlurRegionView: View {
    let region: BlurRegion
    let scale: CGFloat
    let offset: CGPoint
    let imageSize: CGSize
    let displayedImage: NSImage  // For live preview
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onMove: (CGRect) -> Void

    @State private var isHovering = false
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var activeResizeHandle: ResizeHandle?
    @State private var initialRect: CGRect = .zero
    @State private var resizingRect: CGRect?  // Local state during resize for smooth feedback

    enum ResizeHandle: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    private var displayRect: CGRect {
        CGRect(
            x: offset.x + region.rect.origin.x * scale,
            y: offset.y + region.rect.origin.y * scale,
            width: region.rect.width * scale,
            height: region.rect.height * scale
        )
    }

    private var currentDisplayRect: CGRect {
        // During move: use drag offset
        if isDragging && activeResizeHandle == nil {
            return displayRect.offsetBy(dx: dragOffset.width, dy: dragOffset.height)
        }
        // During resize: use local resizingRect for smooth feedback
        if let resizing = resizingRect, activeResizeHandle != nil {
            return CGRect(
                x: offset.x + resizing.origin.x * scale,
                y: offset.y + resizing.origin.y * scale,
                width: resizing.width * scale,
                height: resizing.height * scale
            )
        }
        return displayRect
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
        // Use ZStack to contain everything in same coordinate space
        ZStack {
            // Live blur preview (no hit testing - just visual)
            blurPreviewContent
                .frame(width: currentDisplayRect.width, height: currentDisplayRect.height)
                .clipShape(Rectangle())
                .allowsHitTesting(false)

            // Selection border (no hit testing - just visual)
            Rectangle()
                .strokeBorder(
                    isSelected ? Color.white : styleColor,
                    lineWidth: isSelected ? 3 : (isHovering ? 2.5 : 2)
                )
                .frame(width: currentDisplayRect.width, height: currentDisplayRect.height)
                .allowsHitTesting(false)

            // Style label at bottom (no hit testing)
            styleLabel
                .allowsHitTesting(false)

            // Resize handles (only when selected) - MUST be interactive
            if isSelected {
                resizeHandlesOverlay
            }

            // Delete button - interactive
            if isHovering || isSelected {
                deleteButton
            }
        }
        .frame(width: currentDisplayRect.width, height: currentDisplayRect.height)
        .position(x: currentDisplayRect.midX, y: currentDisplayRect.midY)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .gesture(moveGesture)
        .onHover { isHovering = $0 }
    }

    // MARK: - Live Preview Content

    @ViewBuilder
    private var blurPreviewContent: some View {
        switch region.style {
        case .blur:
            // Use actual cropped & blurred image portion
            BlurredImageRegion(
                image: displayedImage,
                regionRect: region.rect,
                imageSize: imageSize,
                displaySize: currentDisplayRect.size,
                intensity: region.intensity
            )

        case .pixelate:
            // Pixelate preview with mosaic effect
            ZStack {
                BlurredImageRegion(
                    image: displayedImage,
                    regionRect: region.rect,
                    imageSize: imageSize,
                    displaySize: currentDisplayRect.size,
                    intensity: 0.5  // Fixed moderate blur for pixelate base
                )
                PixelGridOverlay(intensity: region.intensity)
            }

        case .solidBlack:
            Color.black

        case .solidWhite:
            Color.white
        }
    }

    // MARK: - Resize Handles

    private var resizeHandlesOverlay: some View {
        ZStack {
            ForEach(ResizeHandle.allCases, id: \.self) { handle in
                resizeHandleView(for: handle)
            }
        }
    }

    @ViewBuilder
    private func resizeHandleView(for handle: ResizeHandle) -> some View {
        let pos = handleOffset(for: handle)
        Circle()
            .fill(Color.white)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(styleColor, lineWidth: 2))
            .shadow(color: .black.opacity(0.3), radius: 2)
            .padding(10)  // Add padding for larger hit area (now 34x34)
            .contentShape(Rectangle())  // Hit area is the padded rectangle
            .highPriorityGesture(resizeGesture(for: handle))  // HIGH priority to beat parent move gesture
            .offset(x: pos.x, y: pos.y)  // MUST be last - moves everything together
    }

    private func handleOffset(for handle: ResizeHandle) -> CGPoint {
        let w = currentDisplayRect.width / 2
        let h = currentDisplayRect.height / 2
        switch handle {
        case .topLeft: return CGPoint(x: -w, y: -h)
        case .topRight: return CGPoint(x: w, y: -h)
        case .bottomLeft: return CGPoint(x: -w, y: h)
        case .bottomRight: return CGPoint(x: w, y: h)
        }
    }

    private func resizeGesture(for handle: ResizeHandle) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if activeResizeHandle == nil {
                    activeResizeHandle = handle
                    initialRect = region.rect
                    resizingRect = region.rect
                }
                // Update LOCAL state only - smooth feedback without state race
                resizingRect = calculateResizedRect(handle: handle, translation: value.translation)
            }
            .onEnded { _ in
                // Commit to appState only on gesture end
                if let finalRect = resizingRect {
                    onMove(finalRect)
                }
                activeResizeHandle = nil
                resizingRect = nil
            }
    }

    // MARK: - Delete Button

    private var deleteButton: some View {
        Button { onDelete() } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.white, .red)
                .shadow(color: .black.opacity(0.5), radius: 2)
        }
        .buttonStyle(.plain)
        .offset(x: currentDisplayRect.width / 2 - 14, y: -currentDisplayRect.height / 2 + 14)
    }

    // MARK: - Style Label

    private var styleLabel: some View {
        HStack(spacing: 4) {
            Text(region.style.rawValue)
            if region.intensity < 1.0 {
                Text("(\(Int(region.intensity * 100))%)")
            }
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(styleColor))
        .offset(y: currentDisplayRect.height / 2 - 16)
    }

    // MARK: - Gestures

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    initialRect = region.rect
                    onSelect()
                }
                dragOffset = value.translation
            }
            .onEnded { _ in
                let imageOffset = CGSize(
                    width: dragOffset.width / scale,
                    height: dragOffset.height / scale
                )
                var newRect = initialRect.offsetBy(dx: imageOffset.width, dy: imageOffset.height)
                newRect.origin.x = max(0, min(newRect.origin.x, imageSize.width - newRect.width))
                newRect.origin.y = max(0, min(newRect.origin.y, imageSize.height - newRect.height))
                onMove(newRect)
                dragOffset = .zero
                isDragging = false
            }
    }

    private func updateRegionForResize(handle: ResizeHandle, translation: CGSize) {
        let dx = translation.width / scale
        let dy = translation.height / scale

        var newRect = initialRect

        switch handle {
        case .topLeft:
            newRect.origin.x += dx
            newRect.origin.y += dy
            newRect.size.width -= dx
            newRect.size.height -= dy
        case .topRight:
            newRect.origin.y += dy
            newRect.size.width += dx
            newRect.size.height -= dy
        case .bottomLeft:
            newRect.origin.x += dx
            newRect.size.width -= dx
            newRect.size.height += dy
        case .bottomRight:
            newRect.size.width += dx
            newRect.size.height += dy
        }

        // Ensure minimum size and clamp to bounds
        if newRect.width >= 10 && newRect.height >= 10 {
            newRect.origin.x = max(0, newRect.origin.x)
            newRect.origin.y = max(0, newRect.origin.y)
            newRect.size.width = min(newRect.width, imageSize.width - newRect.origin.x)
            newRect.size.height = min(newRect.height, imageSize.height - newRect.origin.y)
            onMove(newRect)
        }
    }

    /// Calculate resized rect without committing - for smooth local state updates during drag
    private func calculateResizedRect(handle: ResizeHandle, translation: CGSize) -> CGRect {
        let dx = translation.width / scale
        let dy = translation.height / scale

        var newRect = initialRect

        switch handle {
        case .topLeft:
            newRect.origin.x += dx
            newRect.origin.y += dy
            newRect.size.width -= dx
            newRect.size.height -= dy
        case .topRight:
            newRect.origin.y += dy
            newRect.size.width += dx
            newRect.size.height -= dy
        case .bottomLeft:
            newRect.origin.x += dx
            newRect.size.width -= dx
            newRect.size.height += dy
        case .bottomRight:
            newRect.size.width += dx
            newRect.size.height += dy
        }

        // Ensure minimum size
        guard newRect.width >= 10 && newRect.height >= 10 else {
            return resizingRect ?? initialRect
        }

        // Clamp to image bounds
        newRect.origin.x = max(0, newRect.origin.x)
        newRect.origin.y = max(0, newRect.origin.y)
        newRect.size.width = min(newRect.width, imageSize.width - newRect.origin.x)
        newRect.size.height = min(newRect.height, imageSize.height - newRect.origin.y)

        return newRect
    }
}

/// Grid overlay to simulate pixelation effect
struct PixelGridOverlay: View {
    let intensity: Double

    private var gridSize: CGFloat {
        // Lower intensity = larger pixels (more blur/pixelation)
        CGFloat(4 + (1.0 - intensity) * 12)
    }

    var body: some View {
        Canvas { context, size in
            let cellSize = gridSize
            for x in stride(from: 0, to: size.width, by: cellSize) {
                for y in stride(from: 0, to: size.height, by: cellSize) {
                    let rect = CGRect(x: x, y: y, width: cellSize, height: cellSize)
                    context.stroke(Path(rect), with: .color(.black.opacity(0.2)), lineWidth: 0.5)
                }
            }
        }
    }
}

/// View that shows a cropped and blurred portion of an image
struct BlurredImageRegion: View {
    let image: NSImage
    let regionRect: CGRect  // In image coordinates (pixels)
    let imageSize: CGSize
    let displaySize: CGSize
    let intensity: Double  // 0.0 to 1.0

    var body: some View {
        // Create a cropped NSImage of just the region
        if let croppedImage = cropImage() {
            // Compute blur radius directly here so SwiftUI sees the dependency
            let blurRadius: CGFloat = 3 + CGFloat(intensity) * 25  // Range: 3-28px

            Image(nsImage: croppedImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: displaySize.width, height: displaySize.height)
                .blur(radius: blurRadius)
                .clipped()
                .id(intensity)  // Force blur recalculation when intensity changes
        } else {
            // Fallback: show a blurred material effect
            Rectangle()
                .fill(.ultraThinMaterial)
        }
    }

    private func cropImage() -> NSImage? {
        guard regionRect.width > 0, regionRect.height > 0 else { return nil }

        // Get the CGImage - need to handle coordinate flip
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        // CGImage has origin at BOTTOM-LEFT, but regionRect uses TOP-LEFT origin
        // We must flip the Y coordinate to match CGImage's coordinate system
        let cgImageHeight = CGFloat(cgImage.height)
        let flippedY = cgImageHeight - regionRect.origin.y - regionRect.height

        let cropRect = CGRect(
            x: regionRect.origin.x,
            y: flippedY,
            width: regionRect.width,
            height: regionRect.height
        )

        // Clamp to image bounds
        let imageBounds = CGRect(x: 0, y: 0, width: CGFloat(cgImage.width), height: cgImageHeight)
        let clampedRect = cropRect.intersection(imageBounds)
        guard clampedRect.width > 0, clampedRect.height > 0 else { return nil }

        // Crop the CGImage
        guard let croppedCG = cgImage.cropping(to: clampedRect) else {
            return nil
        }

        // Create NSImage from cropped CGImage
        let croppedNSImage = NSImage(cgImage: croppedCG, size: NSSize(width: croppedCG.width, height: croppedCG.height))
        return croppedNSImage
    }
}

/// Preview of blur regions when in crop mode (shows crop interaction)
struct BlurRegionsCropPreview: View {
    @Environment(AppState.self) private var appState
    let imageSize: CGSize
    let displayedSize: CGSize

    private var scale: CGFloat {
        displayedSize.width / imageSize.width
    }

    var body: some View {
        GeometryReader { geometry in
            let offsetX = (geometry.size.width - displayedSize.width) / 2
            let offsetY = (geometry.size.height - displayedSize.height) / 2

            ForEach(appState.activeImageBlurRegions) { region in
                let isOutside = region.isOutsideCrop(appState.cropSettings, imageSize: imageSize)
                let isPartial = region.isPartiallyCropped(appState.cropSettings, imageSize: imageSize)

                let displayRect = CGRect(
                    x: offsetX + region.rect.origin.x * scale,
                    y: offsetY + region.rect.origin.y * scale,
                    width: region.rect.width * scale,
                    height: region.rect.height * scale
                )

                ZStack {
                    Rectangle()
                        .fill(regionColor(region.style, isOutside: isOutside).opacity(isOutside ? 0.1 : 0.15))
                        .overlay(
                            Rectangle()
                                .strokeBorder(
                                    regionColor(region.style, isOutside: isOutside).opacity(isOutside ? 0.3 : 0.6),
                                    style: StrokeStyle(lineWidth: 1, dash: isOutside ? [2, 2] : [4, 2])
                                )
                        )
                        .frame(width: displayRect.width, height: displayRect.height)
                        .position(x: displayRect.midX, y: displayRect.midY)

                    // Warning indicator for regions outside or partially cropped
                    if isOutside {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.red.opacity(0.7))
                            .position(x: displayRect.midX, y: displayRect.midY)
                    } else if isPartial {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange.opacity(0.8))
                            .position(x: displayRect.maxX - 8, y: displayRect.minY + 8)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func regionColor(_ style: BlurRegion.BlurStyle, isOutside: Bool) -> Color {
        if isOutside { return .red }
        switch style {
        case .blur: return .blue
        case .pixelate: return .purple
        case .solidBlack: return .black
        case .solidWhite: return .gray
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

                // Intensity slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Intensity")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(appState.blurIntensity * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(value: $state.blurIntensity, in: 0.1...1.0, step: 0.1)
                        .controlSize(.small)
                }

                // Instructions
                VStack(alignment: .leading, spacing: 4) {
                    Text("Draw rectangles to blur areas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Click a region to select, drag to move.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Use corner handles to resize.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)

                // Selected region editor
                if let selectedRegion = appState.selectedBlurRegion {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Selected Region")
                            .font(.caption.weight(.medium))

                        HStack {
                            Text("Style")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { selectedRegion.style },
                                set: { appState.updateBlurRegion(selectedRegion.id, style: $0) }
                            )) {
                                ForEach(BlurRegion.BlurStyle.allCases) { style in
                                    Text(style.rawValue).tag(style)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 100)
                        }

                        HStack {
                            Text("Intensity")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Slider(
                                value: Binding(
                                    get: { selectedRegion.intensity },
                                    set: { appState.updateBlurRegion(selectedRegion.id, intensity: $0) }
                                ),
                                in: 0.1...1.0,
                                step: 0.1
                            )
                            .frame(width: 100)
                            Text("\(Int(selectedRegion.intensity * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 32)
                        }

                        HStack {
                            Text("Size: \(Int(selectedRegion.rect.width))×\(Int(selectedRegion.rect.height))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Button("Delete", role: .destructive) {
                                appState.removeBlurRegion(selectedRegion.id)
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
                }

                // Blur regions count and warnings
                if !appState.activeImageBlurRegions.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
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

                        // Crop interaction warnings
                        if appState.cropSettings.hasAnyCrop {
                            if appState.blurRegionsOutsideCropCount > 0 {
                                Label("\(appState.blurRegionsOutsideCropCount) region(s) will be cropped out", systemImage: "xmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            if appState.blurRegionsPartiallyCroppedCount > 0 {
                                Label("\(appState.blurRegionsPartiallyCroppedCount) region(s) partially outside crop", systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
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
