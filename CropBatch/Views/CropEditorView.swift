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
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], phases: .down) { keyPress in
            handleKeyPress(keyPress)
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
        scaledImageView
            .frame(width: scaledImageSize.width, height: scaledImageSize.height)
            .overlay { cropOverlay }
            .overlay { dimensionsOverlay }
            .overlay { cropHandles }
    }

    /// High-quality scaled image using Core Graphics
    @ViewBuilder
    private var scaledImageView: some View {
        if currentScale >= 1.0 {
            // At 100% or above, use original image
            Image(nsImage: image.originalImage)
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
        guard targetSize.width > 0, targetSize.height > 0 else {
            return image.originalImage
        }

        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()

        // Set high-quality interpolation
        NSGraphicsContext.current?.imageInterpolation = .high

        image.originalImage.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: image.originalSize),
            operation: .copy,
            fraction: 1.0
        )

        newImage.unlockFocus()
        return newImage
    }

    private var cropOverlay: some View {
        CropOverlayView(
            imageSize: image.originalSize,
            displayedSize: scaledImageSize,
            cropSettings: appState.cropSettings
        )
    }

    private var dimensionsOverlay: some View {
        CropDimensionsOverlay(
            imageSize: image.originalSize,
            displayedSize: scaledImageSize,
            cropSettings: appState.cropSettings
        )
    }

    private var cropHandles: some View {
        CropHandlesView(
            imageSize: image.originalSize,
            displayedSize: scaledImageSize,
            cropSettings: Binding(
                get: { appState.cropSettings },
                set: { appState.cropSettings = $0 }
            )
        )
    }

    // MARK: - Scale Calculations

    /// Current scale factor based on zoom mode
    private var currentScale: CGFloat {
        guard viewSize.width > 0, viewSize.height > 0 else { return 1 }

        let availableWidth = viewSize.width - 80  // padding
        let availableHeight = viewSize.height - 80

        switch appState.zoomMode {
        case .fit:
            let scaleX = availableWidth / image.originalSize.width
            let scaleY = availableHeight / image.originalSize.height
            return min(scaleX, scaleY, 1.0)  // Don't upscale beyond 100%

        case .fitWidth:
            return availableWidth / image.originalSize.width

        case .fitHeight:
            return availableHeight / image.originalSize.height

        case .actualSize:
            return 1.0
        }
    }

    /// Size of image at current scale
    private var scaledImageSize: CGSize {
        CGSize(
            width: image.originalSize.width * currentScale,
            height: image.originalSize.height * currentScale
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
                    return .handled
                case .downArrow:
                    appState.adjustCrop(edge: .bottom, delta: -baseDelta)
                    return .handled
                case .leftArrow:
                    appState.adjustCrop(edge: .left, delta: -baseDelta)
                    return .handled
                case .rightArrow:
                    appState.adjustCrop(edge: .right, delta: -baseDelta)
                    return .handled
                default:
                    return .ignored
                }
            } else {
                switch keyPress.key {
                case .upArrow:
                    appState.adjustCrop(edge: .bottom, delta: baseDelta)
                    return .handled
                case .downArrow:
                    appState.adjustCrop(edge: .top, delta: baseDelta)
                    return .handled
                case .leftArrow:
                    appState.adjustCrop(edge: .right, delta: baseDelta)
                    return .handled
                case .rightArrow:
                    appState.adjustCrop(edge: .left, delta: baseDelta)
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
                )
                .onTapGesture(count: 2) {
                    onReset()
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

#Preview {
    CropEditorView(image: ImageItem(
        url: URL(fileURLWithPath: "/tmp/test.png"),
        originalImage: NSImage(size: NSSize(width: 800, height: 600))
    ))
    .environment(AppState())
    .frame(width: 600, height: 400)
}
