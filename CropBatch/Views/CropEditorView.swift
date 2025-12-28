import SwiftUI

struct CropEditorView: View {
    @Environment(AppState.self) private var appState
    let image: ImageItem

    @State private var viewSize: CGSize = .zero
    @State private var scrollOffset: CGPoint = .zero
    @FocusState private var isFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            let _ = updateViewSize(geometry.size)

            if needsScrollView {
                scrollableEditor
            } else {
                fittedEditor
            }
        }
        .focusable()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], phases: [.down, .repeat]) { keyPress in
            handleKeyPress(keyPress)
        }
        // Blur tool shortcuts disabled for now
        // .onKeyPress(.init("b")) {
        //     appState.currentTool = appState.currentTool == .blur ? .crop : .blur
        //     return .handled
        // }
        // .onKeyPress(.init("c")) {
        //     appState.currentTool = .crop
        //     return .handled
        // }
        // .onKeyPress(.escape) {
        //     if appState.selectedBlurRegionID != nil {
        //         appState.selectBlurRegion(nil)
        //     } else if appState.currentTool == .blur {
        //         appState.currentTool = .crop
        //     }
        //     return .handled
        // }
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
                    aspectRatioGuideOverlay
                    dimensionsOverlay
                    cropHandles
                }

                // Blur tool disabled for now - needs more work
                // if appState.currentTool == .blur {
                //     BlurToolOverlay(
                //         imageSize: image.originalSize,
                //         displayedSize: scaledImageSize,
                //         displayedImage: image.originalImage
                //     )
                // }
                // if appState.currentTool == .crop && !appState.activeImageBlurRegions.isEmpty {
                //     BlurRegionsCropPreview(
                //         imageSize: image.originalSize,
                //         displayedSize: scaledImageSize
                //     )
                // }
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
    private var highQualityScaledImage: NSImage {
        let targetSize = scaledImageSize
        let sourceImage = displayedImage
        guard targetSize.width > 0, targetSize.height > 0 else {
            return sourceImage
        }

        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()

        // Set high-quality interpolation
        NSGraphicsContext.current?.imageInterpolation = .high

        sourceImage.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: displayedImageSize),
            operation: .copy,
            fraction: 1.0
        )

        newImage.unlockFocus()
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
            cropSettings: appState.cropSettings
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
            onDragEnded: { appState.recordCropChange() }
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
        return ImageCropService.applyTransform(image.originalImage, transform: currentTransform)
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

    // MARK: - Helpers

    private func updateViewSize(_ size: CGSize) {
        if viewSize != size {
            DispatchQueue.main.async {
                viewSize = size
            }
        }
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

// MARK: - Dimensions Overlay

struct CropDimensionsOverlay: View {
    let imageSize: CGSize
    let displayedSize: CGSize
    let cropSettings: CropSettings

    private var scale: CGFloat {
        displayedSize.width / imageSize.width
    }

    private var outputSize: CGSize {
        cropSettings.croppedSize(from: imageSize)
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
                Text("\(Int(outputSize.width)) × \(Int(outputSize.height))")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
                    .position(x: cropRect.midX, y: cropRect.midY)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Crop Handles

struct CropHandlesView: View {
    let imageSize: CGSize
    let displayedSize: CGSize
    @Binding var cropSettings: CropSettings
    var onDragEnded: (() -> Void)? = nil

    private var scale: CGFloat {
        displayedSize.width / imageSize.width
    }

    var body: some View {
        GeometryReader { geometry in
            let offsetX = (geometry.size.width - displayedSize.width) / 2
            let offsetY = (geometry.size.height - displayedSize.height) / 2

            // Top handle with label
            handleWithLabel(
                edge: .top,
                value: cropSettings.cropTop,
                position: CGPoint(
                    x: offsetX + displayedSize.width / 2,
                    y: offsetY + CGFloat(cropSettings.cropTop) * scale
                ),
                labelOffset: CGPoint(x: 0, y: -25),
                onDrag: { location, snapping in
                    let newY = location.y - offsetY
                    var pixelValue = Int(newY / scale)
                    if snapping { pixelValue = (pixelValue / 10) * 10 }
                    cropSettings.cropTop = max(0, min(pixelValue, Int(imageSize.height) - cropSettings.cropBottom - 10))
                },
                onReset: { cropSettings.cropTop = 0 }
            )

            // Bottom handle with label
            handleWithLabel(
                edge: .bottom,
                value: cropSettings.cropBottom,
                position: CGPoint(
                    x: offsetX + displayedSize.width / 2,
                    y: offsetY + displayedSize.height - CGFloat(cropSettings.cropBottom) * scale
                ),
                labelOffset: CGPoint(x: 0, y: 25),
                onDrag: { location, snapping in
                    let newY = location.y - offsetY
                    let fromBottom = displayedSize.height - newY
                    var pixelValue = Int(fromBottom / scale)
                    if snapping { pixelValue = (pixelValue / 10) * 10 }
                    cropSettings.cropBottom = max(0, min(pixelValue, Int(imageSize.height) - cropSettings.cropTop - 10))
                },
                onReset: { cropSettings.cropBottom = 0 }
            )

            // Left handle with label
            handleWithLabel(
                edge: .left,
                value: cropSettings.cropLeft,
                position: CGPoint(
                    x: offsetX + CGFloat(cropSettings.cropLeft) * scale,
                    y: offsetY + displayedSize.height / 2
                ),
                labelOffset: CGPoint(x: -30, y: 0),
                onDrag: { location, snapping in
                    let newX = location.x - offsetX
                    var pixelValue = Int(newX / scale)
                    if snapping { pixelValue = (pixelValue / 10) * 10 }
                    cropSettings.cropLeft = max(0, min(pixelValue, Int(imageSize.width) - cropSettings.cropRight - 10))
                },
                onReset: { cropSettings.cropLeft = 0 }
            )

            // Right handle with label
            handleWithLabel(
                edge: .right,
                value: cropSettings.cropRight,
                position: CGPoint(
                    x: offsetX + displayedSize.width - CGFloat(cropSettings.cropRight) * scale,
                    y: offsetY + displayedSize.height / 2
                ),
                labelOffset: CGPoint(x: 30, y: 0),
                onDrag: { location, snapping in
                    let newX = location.x - offsetX
                    let fromRight = displayedSize.width - newX
                    var pixelValue = Int(fromRight / scale)
                    if snapping { pixelValue = (pixelValue / 10) * 10 }
                    cropSettings.cropRight = max(0, min(pixelValue, Int(imageSize.width) - cropSettings.cropLeft - 10))
                },
                onReset: { cropSettings.cropRight = 0 }
            )

            // MARK: Corner Handles

            // Top-Left corner
            CornerHandle(isSnapping: NSEvent.modifierFlags.contains(.control))
                .position(
                    x: offsetX + CGFloat(cropSettings.cropLeft) * scale,
                    y: offsetY + CGFloat(cropSettings.cropTop) * scale
                )
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            let snapping = NSEvent.modifierFlags.contains(.control)
                            let newX = gesture.location.x - offsetX
                            let newY = gesture.location.y - offsetY
                            var topValue = Int(newY / scale)
                            var leftValue = Int(newX / scale)
                            if snapping {
                                topValue = (topValue / 10) * 10
                                leftValue = (leftValue / 10) * 10
                            }
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
            CornerHandle(isSnapping: NSEvent.modifierFlags.contains(.control))
                .position(
                    x: offsetX + displayedSize.width - CGFloat(cropSettings.cropRight) * scale,
                    y: offsetY + CGFloat(cropSettings.cropTop) * scale
                )
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            let snapping = NSEvent.modifierFlags.contains(.control)
                            let newX = gesture.location.x - offsetX
                            let newY = gesture.location.y - offsetY
                            let fromRight = displayedSize.width - newX
                            var topValue = Int(newY / scale)
                            var rightValue = Int(fromRight / scale)
                            if snapping {
                                topValue = (topValue / 10) * 10
                                rightValue = (rightValue / 10) * 10
                            }
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
            CornerHandle(isSnapping: NSEvent.modifierFlags.contains(.control))
                .position(
                    x: offsetX + CGFloat(cropSettings.cropLeft) * scale,
                    y: offsetY + displayedSize.height - CGFloat(cropSettings.cropBottom) * scale
                )
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            let snapping = NSEvent.modifierFlags.contains(.control)
                            let newX = gesture.location.x - offsetX
                            let newY = gesture.location.y - offsetY
                            let fromBottom = displayedSize.height - newY
                            var bottomValue = Int(fromBottom / scale)
                            var leftValue = Int(newX / scale)
                            if snapping {
                                bottomValue = (bottomValue / 10) * 10
                                leftValue = (leftValue / 10) * 10
                            }
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
            CornerHandle(isSnapping: NSEvent.modifierFlags.contains(.control))
                .position(
                    x: offsetX + displayedSize.width - CGFloat(cropSettings.cropRight) * scale,
                    y: offsetY + displayedSize.height - CGFloat(cropSettings.cropBottom) * scale
                )
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            let snapping = NSEvent.modifierFlags.contains(.control)
                            let newX = gesture.location.x - offsetX
                            let newY = gesture.location.y - offsetY
                            let fromRight = displayedSize.width - newX
                            let fromBottom = displayedSize.height - newY
                            var bottomValue = Int(fromBottom / scale)
                            var rightValue = Int(fromRight / scale)
                            if snapping {
                                bottomValue = (bottomValue / 10) * 10
                                rightValue = (rightValue / 10) * 10
                            }
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
        onDrag: @escaping (CGPoint, Bool) -> Void,
        onReset: @escaping () -> Void
    ) -> some View {
        ZStack {
            EdgeHandle(edge: edge, value: value, isSnapping: NSEvent.modifierFlags.contains(.control))
                .position(position)
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            let snapping = NSEvent.modifierFlags.contains(.control)
                            onDrag(gesture.location, snapping)
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
                PixelLabel(value: value, isSnapping: NSEvent.modifierFlags.contains(.control))
                    .position(x: position.x + labelOffset.x, y: position.y + labelOffset.y)
            }
        }
    }
}

// MARK: - Edge Handle

struct EdgeHandle: View {
    let edge: CropEdge
    let value: Int
    let isSnapping: Bool

    private var isVertical: Bool {
        edge == .left || edge == .right
    }

    var body: some View {
        ZStack {
            Capsule()
                .fill(isSnapping ? Color.orange : Color.accentColor)
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
        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
        .contentShape(Rectangle().size(width: 44, height: 44))
        .cursor(isVertical ? .resizeLeftRight : .resizeUpDown)
    }
}

// MARK: - Corner Handle

struct CornerHandle: View {
    let isSnapping: Bool

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
            .cursor(.crosshair)
    }
}

// MARK: - Pixel Label

struct PixelLabel: View {
    let value: Int
    let isSnapping: Bool

    var body: some View {
        Text("\(value)")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(isSnapping ? Color.orange : Color.accentColor)
            )
            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
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

#Preview {
    CropEditorView(image: ImageItem(
        url: URL(fileURLWithPath: "/tmp/test.png"),
        originalImage: NSImage(size: NSSize(width: 800, height: 600))
    ))
    .environment(AppState())
    .frame(width: 600, height: 400)
}
