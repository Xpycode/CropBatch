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
    @State private var cacheUpdateTask: Task<Void, Never>?

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
        // Update image cache when size/image/transform changes (not during body evaluation)
        .onChange(of: scaledImageSize) { _, newSize in
            updateImageCache(targetSize: newSize)
        }
        .onChange(of: image.id) { _, _ in
            updateImageCache(targetSize: scaledImageSize)
        }
        .onChange(of: currentTransform) { _, _ in
            updateImageCache(targetSize: scaledImageSize)
        }
        .onDisappear {
            cacheUpdateTask?.cancel()
        }
    }

    // MARK: - Cache Management

    /// Updates the scaled image cache asynchronously
    /// Called from onChange modifiers to avoid state mutation during view body evaluation
    private func updateImageCache(targetSize: CGSize) {
        cacheUpdateTask?.cancel()
        cacheUpdateTask = Task { @MainActor in
            guard !Task.isCancelled else { return }

            // Check if cache is already valid
            if cachedImageID == image.id,
               cachedTargetSize == targetSize,
               cachedTransform == currentTransform,
               cachedScaledImage != nil {
                return
            }

            let sourceImage = displayedImage
            guard targetSize.width > 0, targetSize.height > 0 else { return }

            guard let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return
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
            ) else { return }

            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(origin: .zero, size: targetSize))

            guard let scaledCGImage = context.makeImage() else { return }
            guard !Task.isCancelled else { return }

            let newImage = NSImage(cgImage: scaledCGImage, size: targetSize)
            cachedScaledImage = newImage
            cachedImageID = image.id
            cachedTargetSize = targetSize
            cachedTransform = currentTransform
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
        .accessibilityLabel("Zoom \(zoomPercent) percent, \(Int(size.width)) by \(Int(size.height)) pixels")
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

    /// Returns the cached high-quality downscaled image, or the source image if cache is invalid
    /// Cache is updated by onChange modifiers to avoid state mutation during view body evaluation
    private var highQualityScaledImage: NSImage {
        let targetSize = scaledImageSize

        // Return cached image if valid (must check transform too for 180° rotations where size doesn't change)
        if let cached = cachedScaledImage,
           cachedImageID == image.id,
           cachedTargetSize == targetSize,
           cachedTransform == currentTransform {
            return cached
        }

        // Cache miss - return source image (cache will be updated by onChange modifier)
        // This prevents state mutation during view body evaluation which can cause infinite loops
        return displayedImage
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

#Preview {
    CropEditorView(image: ImageItem(
        url: URL(fileURLWithPath: "/tmp/test.png"),
        originalImage: NSImage(size: NSSize(width: 800, height: 600))
    ))
    .environment(AppState())
    .frame(width: 600, height: 400)
}
