import SwiftUI

struct CropEditorView: View {
    @Environment(AppState.self) private var appState
    let image: ImageItem

    @State private var viewSize: CGSize = .zero
    @State private var scrollOffset: CGPoint = .zero
    @FocusState private var isFocused: Bool

    // Image scaling cache to prevent expensive recomputation
    @State private var cachedScaledImage: NSImage?
    @State private var cachedImageID: UUID?
    @State private var cachedTargetSize: CGSize?
    @State private var cachedTransform: ImageTransform?

    var body: some View {
        GeometryReader { geometry in
            Group {
                if needsScrollView {
                    scrollableEditor
                } else {
                    fittedEditor
                }
            }
            .onChange(of: geometry.size, initial: true) { _, newSize in
                viewSize = newSize
            }
        }
        .focusable()
        .focused($isFocused)
        .onTapGesture { isFocused = true }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
            // Trigger snap point detection for active image
            Task {
                await appState.detectSnapPointsForActiveImage()
            }
        }
        .onChange(of: appState.activeImageID) { _, _ in
            // Detect snap points when active image changes
            Task {
                await appState.detectSnapPointsForActiveImage()
            }
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], phases: [.down, .repeat]) { keyPress in
            handleKeyPress(keyPress)
        }
        // Blur tool shortcuts
        .onKeyPress(.init("b")) {
            appState.currentTool = appState.currentTool == .blur ? .crop : .blur
            return .handled
        }
        .onKeyPress(.init("c")) {
            appState.currentTool = .crop
            return .handled
        }
        .onKeyPress(.escape) {
            if appState.selectedBlurRegionID != nil {
                appState.selectBlurRegion(nil)
            } else if appState.currentTool == .blur {
                appState.currentTool = .crop
            }
            return .handled
        }
        // Snap toggle shortcut
        .onKeyPress(.init("s")) {
            appState.snapEnabled.toggle()
            return .handled
        }
    }

    // MARK: - Editors

    /// Whether we need a scroll view (image larger than viewport)
    private var needsScrollView: Bool {
        let imageDisplaySize = scaledImageSize
        return imageDisplaySize.width > viewSize.width - 80 ||
               imageDisplaySize.height > viewSize.height - 80
    }

    /// Editor with ScrollView for large images
    private var scrollableEditor: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            imageWithOverlays
                .frame(width: scaledImageSize.width, height: scaledImageSize.height)
                .padding(40)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    /// Editor that fits within viewport
    private var fittedEditor: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
            imageWithOverlays
                .frame(width: scaledImageSize.width, height: scaledImageSize.height)
        }
    }

    // MARK: - Image Content

    private var imageWithOverlays: some View {
        ZStack {
            scaledImageView
                .frame(width: scaledImageSize.width, height: scaledImageSize.height)

            // Only show overlays when not in Before/After mode
            if !appState.showBeforeAfter {
                // Show crop overlays in crop mode
                if appState.currentTool == .crop {
                    cropOverlay
                    snapGuidesOverlay
                    aspectRatioGuideOverlay
                    dimensionsOverlay
                    cropHandles
                }

                // Blur tool overlay
                if appState.currentTool == .blur {
                    BlurEditorView(
                        originalImageSize: image.originalSize,
                        displayedSize: scaledImageSize,
                        transform: currentTransform,
                        displayedImage: image.originalImage
                    )
                }

                // Show blur regions preview when in crop mode (read-only)
                if appState.currentTool == .crop && !appState.activeImageBlurRegions.isEmpty {
                    BlurRegionsCropPreview(
                        originalImageSize: image.originalSize,
                        displayedSize: scaledImageSize,
                        transform: currentTransform
                    )
                }

                // Watermark preview (shows where watermark will appear on export)
                if appState.exportSettings.watermarkSettings.isValid {
                    WatermarkPreviewOverlay(
                        imageSize: displayedImageSize,
                        displayedSize: scaledImageSize,
                        cropSettings: appState.cropSettings
                    )
                }
            }

            // Top-left info bubble
            VStack {
                HStack {
                    zoomInfoBubble
                    Spacer()
                }
                Spacer()
            }
            .padding(12)

            // Before/After indicator
            if appState.showBeforeAfter {
                VStack {
                    HStack {
                        Spacer()
                        Text("Original")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.black.opacity(0.6)))
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.top, 8)
            }
        }
    }

    private var zoomInfoBubble: some View {
        let zoomPercent = Int(currentScale * 100)
        let size = displayedImageSize
        return HStack(spacing: 6) {
            Text("\(zoomPercent)%")
                .fontWeight(.medium)
            Text("·")
                .foregroundStyle(.secondary)
            Text("\(Int(size.width))×\(Int(size.height))")
            // Show rotation indicator if transformed
            if !currentTransform.isIdentity {
                Text("·")
                    .foregroundStyle(.secondary)
                Image(systemName: currentTransform.rotation != .none ? "rotate.right" : "arrow.left.and.right.righttriangle.left.righttriangle.right")
                    .font(.system(size: 9))
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.5)))
    }

    @ViewBuilder
    private var aspectRatioGuideOverlay: some View {
        if let guide = appState.showAspectRatioGuide {
            AspectRatioGuideView(
                imageSize: image.originalSize,
                displayedSize: scaledImageSize,
                cropSettings: appState.cropSettings,
                aspectRatio: guide
            )
        }
    }

    /// High-quality scaled image using Core Graphics
    @ViewBuilder
    private var scaledImageView: some View {
        if currentScale >= 1.0 {
            // At 100% or above, use displayed image (with transform applied)
            Image(nsImage: displayedImage)
                .interpolation(.high)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            // For downscaling, use CG-scaled image for better quality
            Image(nsImage: highQualityScaledImage)
                .interpolation(.high)
        }
    }

    /// Creates a high-quality downscaled version of the image using Core Graphics
    /// Uses caching to prevent expensive recomputation on every UI update
    private var highQualityScaledImage: NSImage {
        let targetSize = scaledImageSize
        let currentID = image.id

        // Return cached image if valid (must check transform too for 180° rotations where size doesn't change)
        if let cached = cachedScaledImage,
           cachedImageID == currentID,
           cachedTargetSize == targetSize,
           cachedTransform == currentTransform {
            return cached
        }

        // Generate new scaled image
        let sourceImage = displayedImage
        guard targetSize.width > 0, targetSize.height > 0 else {
            return sourceImage
        }

        guard let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return sourceImage
        }

        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(targetSize.width),
            height: Int(targetSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return sourceImage }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(origin: .zero, size: targetSize))

        guard let scaledCGImage = context.makeImage() else { return sourceImage }
        let newImage = NSImage(cgImage: scaledCGImage, size: targetSize)

        // Update cache (async to avoid modifying state during view update)
        Task { @MainActor in
            cachedScaledImage = newImage
            cachedImageID = currentID
            cachedTargetSize = targetSize
            cachedTransform = currentTransform
        }

        return newImage
    }

    private var cropOverlay: some View {
        CropOverlayView(
            imageSize: displayedImageSize,
            displayedSize: scaledImageSize,
            cropSettings: appState.cropSettings
        )
    }

    private var dimensionsOverlay: some View {
        CropDimensionsOverlay(
            imageSize: displayedImageSize,
            displayedSize: scaledImageSize,
            cropSettings: Binding(
                get: { appState.cropSettings },
                set: { appState.cropSettings = $0 }
            ),
            onDragEnded: { appState.recordCropChange() }
        )
    }

    private var cropHandles: some View {
        CropHandlesView(
            imageSize: displayedImageSize,
            displayedSize: scaledImageSize,
            cropSettings: Binding(
                get: { appState.cropSettings },
                set: { appState.cropSettings = $0 }
            ),
            snapPoints: appState.activeSnapPoints,
            snapEnabled: appState.snapEnabled,
            snapThreshold: appState.snapThreshold,
            onDragEnded: { appState.recordCropChange() }
        )
    }

    private var snapGuidesOverlay: some View {
        SnapGuidesView(
            imageSize: displayedImageSize,
            displayedSize: scaledImageSize,
            snapPoints: appState.activeSnapPoints,
            cropSettings: appState.cropSettings,
            snapEnabled: appState.snapEnabled,
            snapThreshold: appState.snapThreshold,
            showDebug: appState.showSnapDebug
        )
    }

    // MARK: - Transform Support

    /// The current transform applied to this image
    private var currentTransform: ImageTransform {
        appState.activeImageTransform
    }

    /// The image with transform applied (for display)
    private var displayedImage: NSImage {
        if currentTransform.isIdentity {
            return image.originalImage
        }
        // Fall back to original if transform fails
        return (try? ImageCropService.applyTransform(image.originalImage, transform: currentTransform)) ?? image.originalImage
    }

    /// Size of the image after transform (accounts for rotation dimension swap)
    private var displayedImageSize: CGSize {
        currentTransform.transformedSize(image.originalSize)
    }

    // MARK: - Scale Calculations

    /// Current scale factor based on zoom mode
    private var currentScale: CGFloat {
        guard viewSize.width > 0, viewSize.height > 0 else { return 1 }

        let availableWidth = viewSize.width - 80  // padding
        let availableHeight = viewSize.height - 80
        let imageSize = displayedImageSize

        switch appState.zoomMode {
        case .fit:
            let scaleX = availableWidth / imageSize.width
            let scaleY = availableHeight / imageSize.height
            return min(scaleX, scaleY, 1.0)  // Don't upscale beyond 100%

        case .fitWidth:
            return availableWidth / imageSize.width

        case .fitHeight:
            return availableHeight / imageSize.height

        case .actualSize:
            return 1.0
        }
    }

    /// Size of image at current scale
    private var scaledImageSize: CGSize {
        CGSize(
            width: displayedImageSize.width * currentScale,
            height: displayedImageSize.height * currentScale
        )
    }

    // MARK: - Keyboard Handling

    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        let hasShift = keyPress.modifiers.contains(.shift)
        let hasControl = keyPress.modifiers.contains(.control)
        let hasOption = keyPress.modifiers.contains(.option)
        let baseDelta = hasControl ? 10 : 1

        if hasShift {
            if hasOption {
                switch keyPress.key {
                case .upArrow:
                    appState.adjustCrop(edge: .top, delta: -baseDelta)
                    appState.recordCropChange()
                    return .handled
                case .downArrow:
                    appState.adjustCrop(edge: .bottom, delta: -baseDelta)
                    appState.recordCropChange()
                    return .handled
                case .leftArrow:
                    appState.adjustCrop(edge: .left, delta: -baseDelta)
                    appState.recordCropChange()
                    return .handled
                case .rightArrow:
                    appState.adjustCrop(edge: .right, delta: -baseDelta)
                    appState.recordCropChange()
                    return .handled
                default:
                    return .ignored
                }
            } else {
                switch keyPress.key {
                case .upArrow:
                    appState.adjustCrop(edge: .bottom, delta: baseDelta)
                    appState.recordCropChange()
                    return .handled
                case .downArrow:
                    appState.adjustCrop(edge: .top, delta: baseDelta)
                    appState.recordCropChange()
                    return .handled
                case .leftArrow:
                    appState.adjustCrop(edge: .right, delta: baseDelta)
                    appState.recordCropChange()
                    return .handled
                case .rightArrow:
                    appState.adjustCrop(edge: .left, delta: baseDelta)
                    appState.recordCropChange()
                    return .handled
                default:
                    return .ignored
                }
            }
        } else {
            switch keyPress.key {
            case .leftArrow:
                appState.selectPreviousImage()
                return .handled
            case .rightArrow:
                appState.selectNextImage()
                return .handled
            default:
                return .ignored
            }
        }
    }
}

// MARK: - Crop Overlay

struct CropOverlayView: View {
    let imageSize: CGSize
    let displayedSize: CGSize
    let cropSettings: CropSettings

    private var scale: CGFloat {
        displayedSize.width / imageSize.width
    }

    var body: some View {
        GeometryReader { geometry in
            let offsetX = (geometry.size.width - displayedSize.width) / 2
            let offsetY = (geometry.size.height - displayedSize.height) / 2

            ZStack {
                cropRectangles(offsetX: offsetX, offsetY: offsetY)
                cropBorder(offsetX: offsetX, offsetY: offsetY)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func cropRectangles(offsetX: CGFloat, offsetY: CGFloat) -> some View {
        // Calculate the middle section bounds (between top and bottom crops)
        let middleTop = offsetY + CGFloat(cropSettings.cropTop) * scale
        let middleHeight = displayedSize.height - CGFloat(cropSettings.cropTop + cropSettings.cropBottom) * scale
        let middleCenterY = middleTop + middleHeight / 2

        // Top crop area (full width)
        Rectangle()
            .fill(Color.black.opacity(0.5))
            .frame(width: displayedSize.width, height: CGFloat(cropSettings.cropTop) * scale)
            .position(x: offsetX + displayedSize.width / 2, y: offsetY + CGFloat(cropSettings.cropTop) * scale / 2)

        // Bottom crop area (full width)
        Rectangle()
            .fill(Color.black.opacity(0.5))
            .frame(width: displayedSize.width, height: CGFloat(cropSettings.cropBottom) * scale)
            .position(x: offsetX + displayedSize.width / 2, y: offsetY + displayedSize.height - CGFloat(cropSettings.cropBottom) * scale / 2)

        // Left crop area (middle section only - between top and bottom)
        Rectangle()
            .fill(Color.black.opacity(0.5))
            .frame(width: CGFloat(cropSettings.cropLeft) * scale, height: middleHeight)
            .position(x: offsetX + CGFloat(cropSettings.cropLeft) * scale / 2, y: middleCenterY)

        // Right crop area (middle section only - between top and bottom)
        Rectangle()
            .fill(Color.black.opacity(0.5))
            .frame(width: CGFloat(cropSettings.cropRight) * scale, height: middleHeight)
            .position(x: offsetX + displayedSize.width - CGFloat(cropSettings.cropRight) * scale / 2, y: middleCenterY)
    }

    @ViewBuilder
    private func cropBorder(offsetX: CGFloat, offsetY: CGFloat) -> some View {
        let cropRect = CGRect(
            x: offsetX + CGFloat(cropSettings.cropLeft) * scale,
            y: offsetY + CGFloat(cropSettings.cropTop) * scale,
            width: displayedSize.width - CGFloat(cropSettings.cropLeft + cropSettings.cropRight) * scale,
            height: displayedSize.height - CGFloat(cropSettings.cropTop + cropSettings.cropBottom) * scale
        )

        Rectangle()
            .strokeBorder(Color.white, lineWidth: 2)
            .frame(width: cropRect.width, height: cropRect.height)
            .position(x: cropRect.midX, y: cropRect.midY)
    }
}

// MARK: - Dimensions Overlay (Draggable)

struct CropDimensionsOverlay: View {
    let imageSize: CGSize
    let displayedSize: CGSize
    @Binding var cropSettings: CropSettings
    var onDragEnded: (() -> Void)? = nil

    @State private var isDragging = false
    @State private var isHovering = false
    // Store initial crop values at drag start (DragGesture gives cumulative translation)
    @State private var dragStartCrop: (left: Int, right: Int, top: Int, bottom: Int)?

    private var scale: CGFloat {
        displayedSize.width / imageSize.width
    }

    private var outputSize: CGSize {
        cropSettings.croppedSize(from: imageSize)
    }

    /// Whether the crop can be moved (has room to slide in any direction)
    private var canMove: Bool {
        cropSettings.hasAnyCrop && (
            cropSettings.cropLeft > 0 || cropSettings.cropRight > 0 ||
            cropSettings.cropTop > 0 || cropSettings.cropBottom > 0
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let offsetX = (geometry.size.width - displayedSize.width) / 2
            let offsetY = (geometry.size.height - displayedSize.height) / 2

            let cropRect = CGRect(
                x: offsetX + CGFloat(cropSettings.cropLeft) * scale,
                y: offsetY + CGFloat(cropSettings.cropTop) * scale,
                width: displayedSize.width - CGFloat(cropSettings.cropLeft + cropSettings.cropRight) * scale,
                height: displayedSize.height - CGFloat(cropSettings.cropTop + cropSettings.cropBottom) * scale
            )

            if cropSettings.hasAnyCrop {
                HStack(spacing: 6) {
                    // Move icon hint
                    if canMove && (isHovering || isDragging) {
                        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Text("\(Int(outputSize.width)) × \(Int(outputSize.height))")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isDragging ? Color.accentColor.opacity(0.8) : Color.black.opacity(0.6))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(isHovering && canMove ? Color.white.opacity(0.5) : Color.clear, lineWidth: 1)
                )
                .position(x: cropRect.midX, y: cropRect.midY)
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            // Capture initial values at drag start
                            if dragStartCrop == nil {
                                dragStartCrop = (
                                    cropSettings.cropLeft,
                                    cropSettings.cropRight,
                                    cropSettings.cropTop,
                                    cropSettings.cropBottom
                                )
                            }
                            isDragging = true
                            handleDrag(translation: gesture.translation)
                        }
                        .onEnded { _ in
                            isDragging = false
                            dragStartCrop = nil
                            onDragEnded?()
                        }
                )
                .onHover { hovering in
                    isHovering = hovering
                    if hovering && canMove {
                        NSCursor.openHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .onChange(of: isDragging) { _, dragging in
                    if dragging && canMove {
                        NSCursor.pop()
                        NSCursor.closedHand.push()
                    } else if !dragging {
                        NSCursor.pop()
                        if isHovering && canMove {
                            NSCursor.openHand.push()
                        }
                    }
                }
            }
        }
    }

    /// Handle drag to move the crop window
    private func handleDrag(translation: CGSize) {
        guard let start = dragStartCrop else { return }

        // Convert screen translation to pixel values
        let deltaX = Int(translation.width / scale)
        let deltaY = Int(translation.height / scale)

        // Calculate new values based on initial + delta
        var newLeft = start.left + deltaX
        var newRight = start.right - deltaX
        var newTop = start.top + deltaY
        var newBottom = start.bottom - deltaY

        // Clamp to valid range (can't go negative)
        if newLeft < 0 {
            newRight += newLeft  // Shift excess back
            newLeft = 0
        }
        if newRight < 0 {
            newLeft += newRight
            newRight = 0
        }
        if newTop < 0 {
            newBottom += newTop
            newTop = 0
        }
        if newBottom < 0 {
            newTop += newBottom
            newBottom = 0
        }

        // Apply clamped values
        cropSettings.cropLeft = max(0, newLeft)
        cropSettings.cropRight = max(0, newRight)
        cropSettings.cropTop = max(0, newTop)
        cropSettings.cropBottom = max(0, newBottom)
    }
}

// MARK: - Crop Handles

struct CropHandlesView: View {
    let imageSize: CGSize
    let displayedSize: CGSize
    @Binding var cropSettings: CropSettings
    var snapPoints: SnapPoints = .empty
    var snapEnabled: Bool = true
    var snapThreshold: Int = 15  // Pixels threshold for snapping
    var onDragEnded: (() -> Void)? = nil

    private var scale: CGFloat {
        displayedSize.width / imageSize.width
    }

    /// Apply snapping to a value based on edge type
    private func applySnap(_ value: Int, edge: CropEdge, gridSnap: Bool, optionBypass: Bool) -> (value: Int, didSnap: Bool) {
        // Grid snapping takes priority (Control key)
        if gridSnap {
            return ((value / 10) * 10, true)
        }

        // Option key bypasses rectangle snapping
        if optionBypass { return (value, false) }

        // Rectangle snapping (only if enabled)
        guard snapEnabled else { return (value, false) }

        switch edge {
        case .top, .bottom:
            if let snapped = snapPoints.nearestHorizontalEdge(to: value, threshold: snapThreshold) {
                return (snapped, true)
            }
        case .left, .right:
            if let snapped = snapPoints.nearestVerticalEdge(to: value, threshold: snapThreshold) {
                return (snapped, true)
            }
        }

        return (value, false)
    }

    /// Check if a value is currently snapped to a rectangle edge
    private func isSnappedToRectangle(_ value: Int, edge: CropEdge) -> Bool {
        guard snapEnabled else { return false }

        switch edge {
        case .top, .bottom:
            return snapPoints.nearestHorizontalEdge(to: value, threshold: 2) != nil
        case .left, .right:
            return snapPoints.nearestVerticalEdge(to: value, threshold: 2) != nil
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let offsetX = (geometry.size.width - displayedSize.width) / 2
            let offsetY = (geometry.size.height - displayedSize.height) / 2

            // Calculate crop rectangle bounds for dynamic handle positioning
            let cropLeft = CGFloat(cropSettings.cropLeft) * scale
            let cropRight = CGFloat(cropSettings.cropRight) * scale
            let cropTop = CGFloat(cropSettings.cropTop) * scale
            let cropBottom = CGFloat(cropSettings.cropBottom) * scale
            let cropWidth = displayedSize.width - cropLeft - cropRight
            let cropHeight = displayedSize.height - cropTop - cropBottom

            // Center X for top/bottom handles (middle of visible crop line)
            let horizontalHandleCenterX = offsetX + cropLeft + cropWidth / 2
            // Center Y for left/right handles (middle of visible crop line)
            let verticalHandleCenterY = offsetY + cropTop + cropHeight / 2

            // Top handle with label
            handleWithLabel(
                edge: .top,
                value: cropSettings.cropTop,
                position: CGPoint(
                    x: horizontalHandleCenterX,
                    y: offsetY + cropTop
                ),
                labelOffset: CGPoint(x: 0, y: -25),
                onDrag: { location, gridSnapping, optionBypass in
                    let newY = location.y - offsetY
                    let rawValue = Int(newY / scale)
                    let (snappedValue, _) = applySnap(rawValue, edge: .top, gridSnap: gridSnapping, optionBypass: optionBypass)
                    cropSettings.cropTop = max(0, min(snappedValue, Int(imageSize.height) - cropSettings.cropBottom - 10))
                },
                onReset: { cropSettings.cropTop = 0 }
            )

            // Bottom handle with label
            handleWithLabel(
                edge: .bottom,
                value: cropSettings.cropBottom,
                position: CGPoint(
                    x: horizontalHandleCenterX,
                    y: offsetY + displayedSize.height - cropBottom
                ),
                labelOffset: CGPoint(x: 0, y: 25),
                onDrag: { location, gridSnapping, optionBypass in
                    let newY = location.y - offsetY
                    let fromBottom = displayedSize.height - newY
                    let rawValue = Int(fromBottom / scale)
                    let (snappedValue, _) = applySnap(rawValue, edge: .bottom, gridSnap: gridSnapping, optionBypass: optionBypass)
                    cropSettings.cropBottom = max(0, min(snappedValue, Int(imageSize.height) - cropSettings.cropTop - 10))
                },
                onReset: { cropSettings.cropBottom = 0 }
            )

            // Left handle with label
            handleWithLabel(
                edge: .left,
                value: cropSettings.cropLeft,
                position: CGPoint(
                    x: offsetX + cropLeft,
                    y: verticalHandleCenterY
                ),
                labelOffset: CGPoint(x: -30, y: 0),
                onDrag: { location, gridSnapping, optionBypass in
                    let newX = location.x - offsetX
                    let rawValue = Int(newX / scale)
                    let (snappedValue, _) = applySnap(rawValue, edge: .left, gridSnap: gridSnapping, optionBypass: optionBypass)
                    cropSettings.cropLeft = max(0, min(snappedValue, Int(imageSize.width) - cropSettings.cropRight - 10))
                },
                onReset: { cropSettings.cropLeft = 0 }
            )

            // Right handle with label
            handleWithLabel(
                edge: .right,
                value: cropSettings.cropRight,
                position: CGPoint(
                    x: offsetX + displayedSize.width - cropRight,
                    y: verticalHandleCenterY
                ),
                labelOffset: CGPoint(x: 30, y: 0),
                onDrag: { location, gridSnapping, optionBypass in
                    let newX = location.x - offsetX
                    let fromRight = displayedSize.width - newX
                    let rawValue = Int(fromRight / scale)
                    let (snappedValue, _) = applySnap(rawValue, edge: .right, gridSnap: gridSnapping, optionBypass: optionBypass)
                    cropSettings.cropRight = max(0, min(snappedValue, Int(imageSize.width) - cropSettings.cropLeft - 10))
                },
                onReset: { cropSettings.cropRight = 0 }
            )

            // MARK: Corner Handles

            // Top-Left corner
            CornerHandle(corner: .topLeft, isSnapping: NSEvent.modifierFlags.contains(.control))
                .position(
                    x: offsetX + CGFloat(cropSettings.cropLeft) * scale,
                    y: offsetY + CGFloat(cropSettings.cropTop) * scale
                )
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            let gridSnapping = NSEvent.modifierFlags.contains(.control)
                            let optionBypass = NSEvent.modifierFlags.contains(.option)
                            let newX = gesture.location.x - offsetX
                            let newY = gesture.location.y - offsetY
                            let rawTop = Int(newY / scale)
                            let rawLeft = Int(newX / scale)
                            let (topValue, _) = applySnap(rawTop, edge: .top, gridSnap: gridSnapping, optionBypass: optionBypass)
                            let (leftValue, _) = applySnap(rawLeft, edge: .left, gridSnap: gridSnapping, optionBypass: optionBypass)
                            cropSettings.cropTop = max(0, min(topValue, Int(imageSize.height) - cropSettings.cropBottom - 10))
                            cropSettings.cropLeft = max(0, min(leftValue, Int(imageSize.width) - cropSettings.cropRight - 10))
                        }
                        .onEnded { _ in onDragEnded?() }
                )
                .onTapGesture(count: 2) {
                    cropSettings.cropTop = 0
                    cropSettings.cropLeft = 0
                    onDragEnded?()
                }

            // Top-Right corner
            CornerHandle(corner: .topRight, isSnapping: NSEvent.modifierFlags.contains(.control))
                .position(
                    x: offsetX + displayedSize.width - CGFloat(cropSettings.cropRight) * scale,
                    y: offsetY + CGFloat(cropSettings.cropTop) * scale
                )
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            let gridSnapping = NSEvent.modifierFlags.contains(.control)
                            let optionBypass = NSEvent.modifierFlags.contains(.option)
                            let newX = gesture.location.x - offsetX
                            let newY = gesture.location.y - offsetY
                            let fromRight = displayedSize.width - newX
                            let rawTop = Int(newY / scale)
                            let rawRight = Int(fromRight / scale)
                            let (topValue, _) = applySnap(rawTop, edge: .top, gridSnap: gridSnapping, optionBypass: optionBypass)
                            let (rightValue, _) = applySnap(rawRight, edge: .right, gridSnap: gridSnapping, optionBypass: optionBypass)
                            cropSettings.cropTop = max(0, min(topValue, Int(imageSize.height) - cropSettings.cropBottom - 10))
                            cropSettings.cropRight = max(0, min(rightValue, Int(imageSize.width) - cropSettings.cropLeft - 10))
                        }
                        .onEnded { _ in onDragEnded?() }
                )
                .onTapGesture(count: 2) {
                    cropSettings.cropTop = 0
                    cropSettings.cropRight = 0
                    onDragEnded?()
                }

            // Bottom-Left corner
            CornerHandle(corner: .bottomLeft, isSnapping: NSEvent.modifierFlags.contains(.control))
                .position(
                    x: offsetX + CGFloat(cropSettings.cropLeft) * scale,
                    y: offsetY + displayedSize.height - CGFloat(cropSettings.cropBottom) * scale
                )
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            let gridSnapping = NSEvent.modifierFlags.contains(.control)
                            let optionBypass = NSEvent.modifierFlags.contains(.option)
                            let newX = gesture.location.x - offsetX
                            let newY = gesture.location.y - offsetY
                            let fromBottom = displayedSize.height - newY
                            let rawBottom = Int(fromBottom / scale)
                            let rawLeft = Int(newX / scale)
                            let (bottomValue, _) = applySnap(rawBottom, edge: .bottom, gridSnap: gridSnapping, optionBypass: optionBypass)
                            let (leftValue, _) = applySnap(rawLeft, edge: .left, gridSnap: gridSnapping, optionBypass: optionBypass)
                            cropSettings.cropBottom = max(0, min(bottomValue, Int(imageSize.height) - cropSettings.cropTop - 10))
                            cropSettings.cropLeft = max(0, min(leftValue, Int(imageSize.width) - cropSettings.cropRight - 10))
                        }
                        .onEnded { _ in onDragEnded?() }
                )
                .onTapGesture(count: 2) {
                    cropSettings.cropBottom = 0
                    cropSettings.cropLeft = 0
                    onDragEnded?()
                }

            // Bottom-Right corner
            CornerHandle(corner: .bottomRight, isSnapping: NSEvent.modifierFlags.contains(.control))
                .position(
                    x: offsetX + displayedSize.width - CGFloat(cropSettings.cropRight) * scale,
                    y: offsetY + displayedSize.height - CGFloat(cropSettings.cropBottom) * scale
                )
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            let gridSnapping = NSEvent.modifierFlags.contains(.control)
                            let optionBypass = NSEvent.modifierFlags.contains(.option)
                            let newX = gesture.location.x - offsetX
                            let newY = gesture.location.y - offsetY
                            let fromRight = displayedSize.width - newX
                            let fromBottom = displayedSize.height - newY
                            let rawBottom = Int(fromBottom / scale)
                            let rawRight = Int(fromRight / scale)
                            let (bottomValue, _) = applySnap(rawBottom, edge: .bottom, gridSnap: gridSnapping, optionBypass: optionBypass)
                            let (rightValue, _) = applySnap(rawRight, edge: .right, gridSnap: gridSnapping, optionBypass: optionBypass)
                            cropSettings.cropBottom = max(0, min(bottomValue, Int(imageSize.height) - cropSettings.cropTop - 10))
                            cropSettings.cropRight = max(0, min(rightValue, Int(imageSize.width) - cropSettings.cropLeft - 10))
                        }
                        .onEnded { _ in onDragEnded?() }
                )
                .onTapGesture(count: 2) {
                    cropSettings.cropBottom = 0
                    cropSettings.cropRight = 0
                    onDragEnded?()
                }
        }
    }

    @ViewBuilder
    private func handleWithLabel(
        edge: CropEdge,
        value: Int,
        position: CGPoint,
        labelOffset: CGPoint,
        onDrag: @escaping (CGPoint, Bool, Bool) -> Void,  // (location, gridSnap, optionBypass)
        onReset: @escaping () -> Void
    ) -> some View {
        let isGridSnapping = NSEvent.modifierFlags.contains(.control)
        let isOptionHeld = NSEvent.modifierFlags.contains(.option)
        let isRectSnapped = !isOptionHeld && isSnappedToRectangle(value, edge: edge)

        ZStack {
            EdgeHandle(
                edge: edge,
                value: value,
                isSnapping: isGridSnapping,
                isRectangleSnapping: isRectSnapped
            )
                .position(position)
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            let gridSnap = NSEvent.modifierFlags.contains(.control)
                            let optionBypass = NSEvent.modifierFlags.contains(.option)
                            onDrag(gesture.location, gridSnap, optionBypass)
                        }
                        .onEnded { _ in
                            onDragEnded?()
                        }
                )
                .onTapGesture(count: 2) {
                    onReset()
                    onDragEnded?()
                }

            // Pixel label (only show if value > 0)
            if value > 0 {
                PixelLabel(
                    value: value,
                    isSnapping: isGridSnapping,
                    isRectangleSnapping: isRectSnapped
                )
                    .position(x: position.x + labelOffset.x, y: position.y + labelOffset.y)
            }
        }
    }
}

// MARK: - Edge Handle

struct EdgeHandle: View {
    let edge: CropEdge
    let value: Int
    let isSnapping: Bool  // Grid snapping (Control key)
    var isRectangleSnapping: Bool = false  // Snapped to detected rectangle edge

    private var isVertical: Bool {
        edge == .left || edge == .right
    }

    private var fillColor: Color {
        if isSnapping {
            return .orange  // Grid snap
        } else if isRectangleSnapping {
            return .green  // Rectangle snap
        } else {
            return .accentColor
        }
    }

    var body: some View {
        ZStack {
            Capsule()
                .fill(fillColor)
                .frame(
                    width: isVertical ? 6 : 60,
                    height: isVertical ? 60 : 6
                )

            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Color.white)
                        .frame(width: 4, height: 4)
                }
            }
            .rotationEffect(isVertical ? .degrees(90) : .zero)
        }
        .shadow(color: isRectangleSnapping ? .green.opacity(0.5) : .black.opacity(0.3), radius: isRectangleSnapping ? 4 : 2, x: 0, y: 1)
        .contentShape(Rectangle().size(width: 44, height: 44))
        .cursor(isVertical ? .resizeLeftRight : .resizeUpDown)
        .accessibilityLabel("\(edge.rawValue.capitalized) crop handle")
        .accessibilityValue("\(value) pixels")
        .accessibilityHint("Drag to adjust \(edge.rawValue) crop")
    }
}

// MARK: - Corner Handle

struct CornerHandle: View {
    let corner: Corner
    let isSnapping: Bool

    enum Corner: String {
        case topLeft = "top-left"
        case topRight = "top-right"
        case bottomLeft = "bottom-left"
        case bottomRight = "bottom-right"
    }

    var body: some View {
        Circle()
            .fill(isSnapping ? Color.orange : Color.accentColor)
            .frame(width: 14, height: 14)
            .overlay(
                Circle()
                    .fill(Color.white)
                    .frame(width: 6, height: 6)
            )
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            .contentShape(Rectangle().size(width: 30, height: 30))
            .accessibilityLabel("\(corner.rawValue) corner handle")
            .accessibilityHint("Drag to adjust crop from \(corner.rawValue) corner")
            .cursor(.crosshair)
    }
}

// MARK: - Pixel Label

struct PixelLabel: View {
    let value: Int
    let isSnapping: Bool  // Grid snapping
    var isRectangleSnapping: Bool = false  // Rectangle snapping

    private var fillColor: Color {
        if isSnapping {
            return .orange
        } else if isRectangleSnapping {
            return .green
        } else {
            return .accentColor
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            if isRectangleSnapping {
                Image(systemName: "rectangle.inset.filled")
                    .font(.system(size: 9))
            }
            Text("\(value)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(fillColor)
        )
        .shadow(color: isRectangleSnapping ? .green.opacity(0.4) : .black.opacity(0.2), radius: isRectangleSnapping ? 4 : 2, x: 0, y: 1)
    }
}

// MARK: - Cursor Extension

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { hovering in
            if hovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Aspect Ratio Guide

struct AspectRatioGuideView: View {
    let imageSize: CGSize
    let displayedSize: CGSize
    let cropSettings: CropSettings
    let aspectRatio: AspectRatioGuide

    private var scale: CGFloat {
        displayedSize.width / imageSize.width
    }

    var body: some View {
        GeometryReader { geometry in
            let offsetX = (geometry.size.width - displayedSize.width) / 2
            let offsetY = (geometry.size.height - displayedSize.height) / 2

            // Calculate the current crop area
            let cropRect = CGRect(
                x: offsetX + CGFloat(cropSettings.cropLeft) * scale,
                y: offsetY + CGFloat(cropSettings.cropTop) * scale,
                width: displayedSize.width - CGFloat(cropSettings.cropLeft + cropSettings.cropRight) * scale,
                height: displayedSize.height - CGFloat(cropSettings.cropTop + cropSettings.cropBottom) * scale
            )

            // Calculate the guide rectangle that fits within the crop area
            let guideRect = calculateGuideRect(within: cropRect)

            // Draw the guide
            ZStack {
                // Guide rectangle outline
                Rectangle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(Color.yellow.opacity(0.8))
                    .frame(width: guideRect.width, height: guideRect.height)
                    .position(x: guideRect.midX, y: guideRect.midY)

                // Aspect ratio label
                Text(aspectRatio.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.yellow)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.5)))
                    .position(x: guideRect.midX, y: guideRect.maxY + 12)
            }
        }
        .allowsHitTesting(false)
    }

    private func calculateGuideRect(within cropRect: CGRect) -> CGRect {
        let targetRatio = aspectRatio.ratio
        let currentRatio = cropRect.width / cropRect.height

        var guideWidth: CGFloat
        var guideHeight: CGFloat

        if currentRatio > targetRatio {
            // Crop area is wider than target - fit to height
            guideHeight = cropRect.height
            guideWidth = guideHeight * targetRatio
        } else {
            // Crop area is taller than target - fit to width
            guideWidth = cropRect.width
            guideHeight = guideWidth / targetRatio
        }

        return CGRect(
            x: cropRect.midX - guideWidth / 2,
            y: cropRect.midY - guideHeight / 2,
            width: guideWidth,
            height: guideHeight
        )
    }
}

// MARK: - Snap Guides Overlay

// MARK: - Watermark Preview Overlay

struct WatermarkPreviewOverlay: View {
    let imageSize: CGSize        // Original image size in pixels
    let displayedSize: CGSize    // Displayed size on screen
    let cropSettings: CropSettings
    @Environment(AppState.self) private var appState

    @State private var isDragging = false
    @State private var dragStartOffset: CGPoint = .zero

    private var scale: CGFloat {
        displayedSize.width / imageSize.width
    }

    /// The crop region in displayed coordinates
    private var cropRect: CGRect {
        let left = CGFloat(cropSettings.cropLeft) * scale
        let top = CGFloat(cropSettings.cropTop) * scale
        let right = CGFloat(cropSettings.cropRight) * scale
        let bottom = CGFloat(cropSettings.cropBottom) * scale

        return CGRect(
            x: left,
            y: top,
            width: displayedSize.width - left - right,
            height: displayedSize.height - top - bottom
        )
    }

    var body: some View {
        let settings = appState.exportSettings.watermarkSettings

        if settings.isValid {
            // Container sized to crop area with clipping AFTER overlay
            Color.clear
                .frame(width: cropRect.width, height: cropRect.height)
                .overlay(alignment: .topLeading) {
                    switch settings.mode {
                    case .image:
                        imageWatermarkContent(settings: settings)
                    case .text:
                        textWatermarkContent(settings: settings)
                    }
                }
                .clipShape(Rectangle())  // Clip AFTER overlay to constrain watermark
                .position(
                    x: cropRect.midX,
                    y: cropRect.midY
                )
        }
    }

    // MARK: - Image Watermark Preview

    @ViewBuilder
    private func imageWatermarkContent(settings: WatermarkSettings) -> some View {
        if let watermarkImage = settings.cachedImage {
            let wmSize = watermarkSize(for: cropRect.size, watermark: watermarkImage)
            let wmPosition = watermarkPosition(for: cropRect.size, wmSize: wmSize)

            Image(nsImage: watermarkImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: wmSize.width, height: wmSize.height)
                .opacity(isDragging ? min(settings.opacity + 0.3, 1.0) : settings.opacity)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(isDragging ? Color.accentColor : Color.clear, lineWidth: 2)
                )
                .offset(x: wmPosition.x, y: wmPosition.y)
                .gesture(dragGesture)
                .onHover { hovering in
                    if hovering {
                        NSCursor.openHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .accessibilityLabel("Watermark image preview")
                .accessibilityHint("Drag to reposition watermark")
        }
    }

    // MARK: - Text Watermark Preview

    @ViewBuilder
    private func textWatermarkContent(settings: WatermarkSettings) -> some View {
        // Preview text with placeholder substitution
        let previewText = TextWatermarkVariable.substitute(
            in: settings.text,
            filename: "preview",
            index: 1,
            count: appState.images.count
        )

        let textSize = textSize(for: previewText, settings: settings)
        let wmPosition = watermarkPosition(for: cropRect.size, wmSize: textSize)

        // Use scaled font to match size calculation
        let scaledFont = NSFont(
            descriptor: settings.textFont.fontDescriptor,
            size: settings.fontSize * scale
        ) ?? settings.textFont

        Text(previewText)
            .font(Font(scaledFont))
            .foregroundColor(Color(nsColor: settings.textColor.nsColor))
            .opacity(isDragging ? min(settings.opacity + 0.3, 1.0) : settings.opacity)
            .shadow(
                color: settings.shadow.isEnabled
                    ? Color(nsColor: settings.shadow.color.nsColor)
                    : .clear,
                radius: settings.shadow.isEnabled ? settings.shadow.blur * scale : 0,
                x: settings.shadow.isEnabled ? settings.shadow.offsetX * scale : 0,
                y: settings.shadow.isEnabled ? settings.shadow.offsetY * scale : 0
            )
            .overlay(
                // Show outline as stroke (SwiftUI doesn't have native stroke text)
                settings.outline.isEnabled ?
                Text(previewText)
                    .font(Font(scaledFont))
                    .foregroundColor(.clear)
                    .overlay(
                        Text(previewText)
                            .font(Font(scaledFont))
                            .foregroundColor(Color(nsColor: settings.outline.color.nsColor))
                    )
                    .opacity(0.5)
                : nil
            )
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isDragging ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .offset(x: wmPosition.x, y: wmPosition.y)
            .gesture(dragGesture)
            .onHover { hovering in
                if hovering {
                    NSCursor.openHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .accessibilityLabel("Watermark text: \(previewText)")
            .accessibilityHint("Drag to reposition watermark")
    }

    // MARK: - Shared

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragStartOffset = CGPoint(
                        x: appState.exportSettings.watermarkSettings.offsetX,
                        y: appState.exportSettings.watermarkSettings.offsetY
                    )
                }
                // Convert drag translation to pixel coordinates
                let deltaX = value.translation.width / scale
                let deltaY = value.translation.height / scale
                appState.exportSettings.watermarkSettings.offsetX = dragStartOffset.x + deltaX
                appState.exportSettings.watermarkSettings.offsetY = dragStartOffset.y + deltaY
            }
            .onEnded { _ in
                isDragging = false
                appState.markCustomSettings()
            }
    }

    private func textSize(for text: String, settings: WatermarkSettings) -> CGSize {
        let attrs = settings.textAttributes(scale: scale)
        let attrString = NSAttributedString(string: text, attributes: attrs)
        let size = attrString.size()
        return CGSize(width: size.width + 8, height: size.height + 8)  // Add padding
    }

    private func watermarkSize(for containerSize: CGSize, watermark: NSImage) -> CGSize {
        let settings = appState.exportSettings.watermarkSettings
        let originalSize = watermark.size
        guard originalSize.width > 0 && originalSize.height > 0 else {
            return .zero
        }

        let aspectRatio = originalSize.width / originalSize.height

        switch settings.sizeMode {
        case .original:
            // Scale down if watermark is larger than container
            let scaledWidth = min(originalSize.width * scale, containerSize.width * 0.5)
            return CGSize(width: scaledWidth, height: scaledWidth / aspectRatio)

        case .percentage:
            let targetWidth = containerSize.width * (settings.sizeValue / 100.0)
            return CGSize(width: targetWidth, height: targetWidth / aspectRatio)

        case .fixedWidth:
            let scaledWidth = settings.sizeValue * scale
            return CGSize(width: scaledWidth, height: scaledWidth / aspectRatio)

        case .fixedHeight:
            let scaledHeight = settings.sizeValue * scale
            return CGSize(width: scaledHeight * aspectRatio, height: scaledHeight)
        }
    }

    private func watermarkPosition(for containerSize: CGSize, wmSize: CGSize) -> CGPoint {
        let settings = appState.exportSettings.watermarkSettings
        let margin = settings.margin * scale
        let anchor = settings.position.normalizedAnchor

        let availableWidth = containerSize.width - (2 * margin)
        let availableHeight = containerSize.height - (2 * margin)

        // Include user offsets (scaled to display size)
        var x = margin + (availableWidth - wmSize.width) * anchor.x + (settings.offsetX * scale)
        var y = margin + (availableHeight - wmSize.height) * anchor.y + (settings.offsetY * scale)

        // Clamp position to keep watermark within bounds
        let minX: CGFloat = 0
        let maxX = containerSize.width - wmSize.width
        let minY: CGFloat = 0
        let maxY = containerSize.height - wmSize.height

        x = max(minX, min(maxX, x))
        y = max(minY, min(maxY, y))

        return CGPoint(x: x, y: y)
    }
}

struct SnapGuidesView: View {
    let imageSize: CGSize
    let displayedSize: CGSize
    let snapPoints: SnapPoints
    let cropSettings: CropSettings
    var snapEnabled: Bool = true
    var snapThreshold: Int = 15
    var showDebug: Bool = false

    private var scale: CGFloat {
        displayedSize.width / imageSize.width
    }

    var body: some View {
        GeometryReader { geometry in
            if snapEnabled || showDebug {
                let offsetX = (geometry.size.width - displayedSize.width) / 2
                let offsetY = (geometry.size.height - displayedSize.height) / 2

                // Only show guides that are near current crop edges (within snap range)
                let cropTop = cropSettings.cropTop
                let cropBottom = Int(imageSize.height) - cropSettings.cropBottom
                let cropLeft = cropSettings.cropLeft
                let cropRight = Int(imageSize.width) - cropSettings.cropRight

                // Horizontal guide lines (for top/bottom edges)
                ForEach(snapPoints.horizontalEdges.filter { edge in
                    // In debug mode, show all; otherwise show if near a crop edge
                    showDebug || abs(edge - cropTop) <= snapThreshold + 5 || abs(edge - cropBottom) <= snapThreshold + 5
                }, id: \.self) { edge in
                    let y = offsetY + CGFloat(edge) * scale
                    let isSnapped = abs(edge - cropTop) <= 2 || abs(edge - (Int(imageSize.height) - cropSettings.cropBottom)) <= 2

                    Rectangle()
                        .fill(showDebug && !isSnapped ? Color.orange.opacity(0.5) : (isSnapped ? Color.green : Color.green.opacity(0.4)))
                        .frame(width: displayedSize.width, height: isSnapped ? 2 : 1)
                        .position(x: offsetX + displayedSize.width / 2, y: y)
                }

                // Vertical guide lines (for left/right edges)
                ForEach(snapPoints.verticalEdges.filter { edge in
                    // In debug mode, show all; otherwise show if near a crop edge
                    showDebug || abs(edge - cropLeft) <= snapThreshold + 5 || abs(edge - cropRight) <= snapThreshold + 5
                }, id: \.self) { edge in
                    let x = offsetX + CGFloat(edge) * scale
                    let isSnapped = abs(edge - cropLeft) <= 2 || abs(edge - (Int(imageSize.width) - cropSettings.cropRight)) <= 2

                    Rectangle()
                        .fill(showDebug && !isSnapped ? Color.orange.opacity(0.5) : (isSnapped ? Color.green : Color.green.opacity(0.4)))
                        .frame(width: isSnapped ? 2 : 1, height: displayedSize.height)
                        .position(x: x, y: offsetY + displayedSize.height / 2)
                }

                // Debug: show center cross if center snapping is implied
                if showDebug {
                    let centerX = Int(imageSize.width) / 2
                    let centerY = Int(imageSize.height) / 2
                    let isCenterHSnapped = snapPoints.horizontalEdges.contains(centerY)
                    let isCenterVSnapped = snapPoints.verticalEdges.contains(centerX)

                    if isCenterHSnapped {
                        Rectangle()
                            .fill(Color.blue.opacity(0.5))
                            .frame(width: displayedSize.width, height: 1)
                            .position(x: offsetX + displayedSize.width / 2, y: offsetY + CGFloat(centerY) * scale)
                    }
                    if isCenterVSnapped {
                        Rectangle()
                            .fill(Color.blue.opacity(0.5))
                            .frame(width: 1, height: displayedSize.height)
                            .position(x: offsetX + CGFloat(centerX) * scale, y: offsetY + displayedSize.height / 2)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    CropEditorView(image: ImageItem(
        url: URL(fileURLWithPath: "/tmp/test.png"),
        originalImage: NSImage(size: NSSize(width: 800, height: 600))
    ))
    .environment(AppState())
    .frame(width: 600, height: 400)
}
