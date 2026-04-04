import SwiftUI
import AppKit
import Combine

// MARK: - Blur Preview Cache

/// Pre-renders a single composite NSImage with all blur regions baked in at display resolution.
/// Each BlurRegionOverlay then clips from this cached image instead of running independent
/// SwiftUI .blur() modifiers, reducing GPU compositing work from O(n) full-image blurs to one.
@Observable
final class BlurPreviewCache {
    var cachedImage: NSImage?

    private var cachedImageID: UUID?
    private var cachedRegionHash: Int = 0
    private var cachedDisplayedSize: CGSize = .zero

    private var debounceTask: Task<Void, Never>?

    /// Schedules a cache update, debounced by 100ms to avoid thrashing during rapid changes.
    @MainActor
    func scheduleUpdate(
        displayedImage: NSImage,
        imageID: UUID?,
        regions: [BlurRegion],
        displayedSize: CGSize,
        transform: ImageTransform
    ) {
        let newHash = Self.hash(regions: regions, size: displayedSize)
        let unchanged = imageID == cachedImageID
            && newHash == cachedRegionHash
            && displayedSize == cachedDisplayedSize

        guard !unchanged else { return }

        debounceTask?.cancel()

        // Capture only value types so the task closure is safe under Swift 6 concurrency.
        let capturedRegions = regions
        let capturedSize = displayedSize
        let capturedTransform = transform
        let capturedImageID = imageID
        let capturedHash = newHash

        debounceTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return  // Task was cancelled — a newer update supersedes this one
            }
            guard !Task.isCancelled else { return }

            let displayResImage = Self.createDisplayResolutionImage(from: displayedImage, size: capturedSize)
            let transformedRegions = capturedRegions.map { region in
                BlurRegion(
                    id: region.id,
                    normalizedRect: region.normalizedRect.applyingTransform(capturedTransform),
                    style: region.style,
                    intensity: region.intensity
                )
            }

            let rendered = ImageCropService.applyBlurRegions(displayResImage, regions: transformedRegions)

            self.cachedImage = rendered
            self.cachedImageID = capturedImageID
            self.cachedRegionHash = capturedHash
            self.cachedDisplayedSize = capturedSize
        }
    }

    @MainActor
    func invalidate() {
        debounceTask?.cancel()
        cachedImage = nil
        cachedImageID = nil
        cachedRegionHash = 0
        cachedDisplayedSize = .zero
    }

    // MARK: - Helpers

    private static func hash(regions: [BlurRegion], size: CGSize) -> Int {
        var hasher = Hasher()
        for region in regions {
            hasher.combine(region.normalizedRect)
            hasher.combine(region.style)
            hasher.combine(region.intensity)
        }
        hasher.combine(size.width)
        hasher.combine(size.height)
        return hasher.finalize()
    }

    /// Produces a display-resolution copy of the source image so applyBlurRegions
    /// operates on a small bitmap rather than the full 4K original.
    private static func createDisplayResolutionImage(from source: NSImage, size: CGSize) -> NSImage {
        guard size.width > 0, size.height > 0 else { return source }
        guard let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return source }
        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return source }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        guard let scaled = context.makeImage() else { return source }
        return NSImage(cgImage: scaled, size: size)
    }
}

// MARK: - Gesture State Machine

/// Unified gesture state for blur region interaction
/// This prevents gesture conflicts by having a single source of truth
enum BlurGestureState: Equatable {
    case idle
    case drawing(start: CGPoint, current: CGPoint)
    case moving(regionID: UUID, startRect: NormalizedRect, offset: CGSize)
    case resizing(regionID: UUID, handle: ResizeHandle, startRect: NormalizedRect)

    enum ResizeHandle: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }
}

// MARK: - Blur Editor View

/// Main blur editor overlay with unified gesture handling
struct BlurEditorView: View {
    @Environment(AppState.self) private var appState

    /// Original image size (pre-transform)
    let originalImageSize: CGSize

    /// Displayed size on screen (post-transform and scale)
    let displayedSize: CGSize

    /// Current transform applied to the image
    let transform: ImageTransform

    /// The displayed image for preview rendering
    let displayedImage: NSImage

    /// Whether drawing new blur regions is enabled (toggle + B key)
    let isDrawingEnabled: Bool

    @State private var gestureState: BlurGestureState = .idle
    @State private var converter: CoordinateConverter?
    @State private var previewCache = BlurPreviewCache()

    /// Image size after transform (accounts for rotation swapping dimensions)
    private var transformedImageSize: CGSize {
        transform.transformedSize(originalImageSize)
    }

    var body: some View {
        // Coordinate converter - no offset needed since overlay matches image frame exactly
        let currentConverter = CoordinateConverter(
            imageSize: transformedImageSize,
            displayedSize: displayedSize,
            displayOffset: .zero
        )

        ZStack {
            // Background for drawing new regions
            drawingLayer(converter: currentConverter)

            // Existing blur regions (stored in ORIGINAL coords, display in TRANSFORMED coords)
            ForEach(appState.activeImageBlurRegions) { region in
                // Transform the stored normalized rect for display
                let displayNormalizedRect = region.normalizedRect.applyingTransform(transform)

                BlurRegionOverlay(
                    region: region,
                    displayNormalizedRect: displayNormalizedRect,
                    converter: currentConverter,
                    transform: transform,
                    originalImageSize: originalImageSize,
                    gestureState: $gestureState,
                    isSelected: appState.selectedBlurRegionID == region.id,
                    displayedImage: displayedImage,
                    cachedBlurImage: previewCache.cachedImage,
                    onSelect: { appState.selectBlurRegion(region.id) },
                    onDelete: { appState.removeBlurRegion(region.id) },
                    onUpdate: { newNormalizedRect in
                        // newNormalizedRect is in TRANSFORMED coords, convert to ORIGINAL for storage
                        let originalRect = newNormalizedRect.applyingInverseTransform(transform)
                        appState.updateBlurRegion(region.id, normalizedRect: originalRect)
                    }
                )
            }

            // Drawing preview (when in drawing state)
            if case .drawing(let start, let current) = gestureState {
                drawingPreview(start: start, current: current)
            }
        }
        .onAppear {
            converter = currentConverter
            scheduleCacheUpdate()
        }
        .onChange(of: displayedSize) { _, _ in
            converter = currentConverter
            scheduleCacheUpdate()
        }
        .onChange(of: appState.activeImageBlurRegions) { _, _ in scheduleCacheUpdate() }
        .onChange(of: displayedImage) { _, _ in
            previewCache.invalidate()
            scheduleCacheUpdate()
        }
    }

    private func scheduleCacheUpdate() {
        previewCache.scheduleUpdate(
            displayedImage: displayedImage,
            imageID: appState.activeImageID,
            regions: appState.activeImageBlurRegions,
            displayedSize: displayedSize,
            transform: transform
        )
    }

    // MARK: - Drawing Layer

    @ViewBuilder
    private func drawingLayer(converter: CoordinateConverter) -> some View {
        if isDrawingEnabled {
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    appState.selectBlurRegion(nil)
                }
                .gesture(drawingGesture(converter: converter))
        } else {
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    appState.selectBlurRegion(nil)
                }
                .allowsHitTesting(!appState.activeImageBlurRegions.isEmpty)
        }
    }

    private func drawingGesture(converter: CoordinateConverter) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                // Only start drawing if not interacting with a region
                guard case .idle = gestureState else { return }

                // Check if starting on an existing region - if so, don't draw
                let startNorm = converter.viewToNormalized(value.startLocation)
                let clickedRegion = appState.activeImageBlurRegions.first { region in
                    region.normalizedRect.contains(startNorm)
                }
                guard clickedRegion == nil else { return }

                gestureState = .drawing(start: value.startLocation, current: value.location)
            }
            .onChanged { value in
                if case .drawing(let start, _) = gestureState {
                    gestureState = .drawing(start: start, current: value.location)
                }
            }
            .onEnded { value in
                if case .drawing(let start, let end) = gestureState {
                    finishDrawing(start: start, end: end, converter: converter)
                }
                gestureState = .idle
            }
    }

    private func finishDrawing(start: CGPoint, end: CGPoint, converter: CoordinateConverter) {
        let startNorm = converter.viewToNormalized(start)
        let endNorm = converter.viewToNormalized(end)

        // This rect is in TRANSFORMED view coordinates
        let transformedRect = NormalizedRect(
            x: min(startNorm.x, endNorm.x),
            y: min(startNorm.y, endNorm.y),
            width: abs(endNorm.x - startNorm.x),
            height: abs(endNorm.y - startNorm.y)
        ).clamped()

        // Minimum size check
        let minSize = Config.Blur.minimumRegionSize
        guard transformedRect.width >= minSize && transformedRect.height >= minSize else { return }

        // Convert to ORIGINAL image coordinates for storage
        let originalRect = transformedRect.applyingInverseTransform(transform)

        let region = BlurRegion(
            normalizedRect: originalRect,
            style: appState.blurStyle,
            intensity: appState.blurIntensity
        )
        appState.addBlurRegion(region)
        appState.selectBlurRegion(region.id)
    }

    // MARK: - Drawing Preview

    @ViewBuilder
    private func drawingPreview(start: CGPoint, current: CGPoint) -> some View {
        let rect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )

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

    private var previewColor: Color {
        switch appState.blurStyle {
        case .blur: return .blue
        case .pixelate: return .purple
        case .solidBlack: return .black
        case .solidWhite: return .gray
        }
    }
}

// MARK: - Blur Region Overlay

/// Individual blur region with move/resize handles
struct BlurRegionOverlay: View {
    /// The region data (stored in ORIGINAL image coordinates)
    let region: BlurRegion

    /// The region rect transformed for display (in TRANSFORMED view coordinates)
    let displayNormalizedRect: NormalizedRect

    let converter: CoordinateConverter
    let transform: ImageTransform
    let originalImageSize: CGSize
    @Binding var gestureState: BlurGestureState
    let isSelected: Bool
    let displayedImage: NSImage
    /// Pre-composited image with all blur regions applied, used as an efficient clip source.
    /// Nil on cache miss — falls back to SwiftUI .blur() modifier.
    let cachedBlurImage: NSImage?
    let onSelect: () -> Void
    let onDelete: () -> Void
    /// Callback with rect in TRANSFORMED coordinates
    let onUpdate: (NormalizedRect) -> Void

    @State private var isHovering = false

    /// The current rect in TRANSFORMED coordinates (accounts for live drag/resize)
    private var currentDisplayRect: NormalizedRect {
        // During move/resize, show the live position
        switch gestureState {
        case .moving(let id, let startRect, let offset) where id == region.id:
            // startRect is in ORIGINAL coords, transform to display coords
            let displayStartRect = startRect.applyingTransform(transform)
            let dx = offset.width / converter.displayedSize.width
            let dy = offset.height / converter.displayedSize.height
            return displayStartRect.offsetBy(dx: dx, dy: dy).clamped()

        case .resizing(let id, _, _) where id == region.id:
            // During resize, use the current stored rect (transformed for display)
            return displayNormalizedRect

        default:
            return displayNormalizedRect
        }
    }

    private var displayRect: CGRect {
        converter.normalizedToView(currentDisplayRect)
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
            // Preview content
            previewContent
                .frame(width: displayRect.width, height: displayRect.height)
                .clipShape(Rectangle())
                .allowsHitTesting(false)

            // Selection border
            Rectangle()
                .strokeBorder(
                    isSelected ? Color.white : styleColor,
                    lineWidth: isSelected ? 3 : (isHovering ? 2.5 : 2)
                )
                .frame(width: displayRect.width, height: displayRect.height)
                .allowsHitTesting(false)

            // Style label
            styleLabel
                .allowsHitTesting(false)

            // Resize handles (when selected)
            if isSelected {
                resizeHandles
            }

            // Delete button
            if isHovering || isSelected {
                deleteButton
            }
        }
        .frame(width: displayRect.width, height: displayRect.height)
        .position(x: displayRect.midX, y: displayRect.midY)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .gesture(moveGesture)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(region.style.rawValue) region")
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityHint("Tap to select, drag to move")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Preview Content

    @ViewBuilder
    private var previewContent: some View {
        switch region.style {
        case .blur:
            if let cached = cachedBlurImage {
                // Cache hit: clip the pre-composited image — single composite, no per-region .blur()
                GeometryReader { _ in
                    Image(nsImage: cached)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: converter.displayedSize.width, height: converter.displayedSize.height)
                        .offset(x: -displayRect.minX, y: -displayRect.minY)
                }
                .frame(width: displayRect.width, height: displayRect.height)
                .clipped()
            } else {
                // Cache miss (first frame or rapid change): fall back to SwiftUI .blur()
                GeometryReader { _ in
                    Image(nsImage: displayedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: converter.displayedSize.width, height: converter.displayedSize.height)
                        .blur(radius: 30 * region.intensity)
                        .offset(x: -displayRect.minX, y: -displayRect.minY)
                }
                .frame(width: displayRect.width, height: displayRect.height)
                .clipped()
            }

        case .pixelate:
            if let cached = cachedBlurImage {
                // Cache hit: CIPixellate already baked into the composite
                GeometryReader { _ in
                    Image(nsImage: cached)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: converter.displayedSize.width, height: converter.displayedSize.height)
                        .offset(x: -displayRect.minX, y: -displayRect.minY)
                }
                .frame(width: displayRect.width, height: displayRect.height)
                .clipped()
            } else {
                // Cache miss: show tinted placeholder while CIPixellate renders
                ZStack {
                    Color.purple.opacity(0.25)
                    ProgressView()
                        .controlSize(.small)
                }
            }

        case .solidBlack:
            Color.black

        case .solidWhite:
            Color.white
        }
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
        .offset(y: displayRect.height / 2 - 16)
    }

    // MARK: - Resize Handles

    private var resizeHandles: some View {
        ForEach(BlurGestureState.ResizeHandle.allCases, id: \.self) { handle in
            resizeHandle(for: handle)
        }
    }

    @ViewBuilder
    private func resizeHandle(for handle: BlurGestureState.ResizeHandle) -> some View {
        let pos = handlePosition(for: handle)
        Circle()
            .fill(Color.white)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(styleColor, lineWidth: 2))
            .shadow(color: .black.opacity(0.3), radius: 2)
            .padding(10)
            .contentShape(Rectangle())
            .gesture(resizeGesture(for: handle))
            .offset(x: pos.x, y: pos.y)
    }

    private func handlePosition(for handle: BlurGestureState.ResizeHandle) -> CGPoint {
        let w = displayRect.width / 2
        let h = displayRect.height / 2
        switch handle {
        case .topLeft: return CGPoint(x: -w, y: -h)
        case .topRight: return CGPoint(x: w, y: -h)
        case .bottomLeft: return CGPoint(x: -w, y: h)
        case .bottomRight: return CGPoint(x: w, y: h)
        }
    }

    private func resizeGesture(for handle: BlurGestureState.ResizeHandle) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if case .idle = gestureState {
                    // Store original rect (in ORIGINAL coords) for reference
                    gestureState = .resizing(regionID: region.id, handle: handle, startRect: region.normalizedRect)
                }

                if case .resizing(let id, let h, let startRect) = gestureState, id == region.id {
                    // Work in TRANSFORMED space for the calculation
                    let transformedStartRect = startRect.applyingTransform(transform)
                    let newTransformedRect = calculateResizedRect(
                        startRect: transformedStartRect,
                        handle: h,
                        translation: value.translation,
                        converter: converter
                    )
                    // onUpdate expects TRANSFORMED coords (parent will inverse-transform)
                    onUpdate(newTransformedRect)
                }
            }
            .onEnded { _ in
                gestureState = .idle
            }
    }

    private func calculateResizedRect(
        startRect: NormalizedRect,
        handle: BlurGestureState.ResizeHandle,
        translation: CGSize,
        converter: CoordinateConverter
    ) -> NormalizedRect {
        let dx = translation.width / converter.displayedSize.width
        let dy = translation.height / converter.displayedSize.height

        var newRect = startRect

        switch handle {
        case .topLeft:
            newRect.x += dx
            newRect.y += dy
            newRect.width -= dx
            newRect.height -= dy
        case .topRight:
            newRect.y += dy
            newRect.width += dx
            newRect.height -= dy
        case .bottomLeft:
            newRect.x += dx
            newRect.width -= dx
            newRect.height += dy
        case .bottomRight:
            newRect.width += dx
            newRect.height += dy
        }

        // Minimum size check
        let minSize = Config.Blur.minimumRegionSize
        guard newRect.width >= minSize && newRect.height >= minSize else {
            // Return original transformed rect if too small
            return displayNormalizedRect
        }

        return newRect.clamped()
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
        .offset(x: displayRect.width / 2 - 14, y: -displayRect.height / 2 + 14)
    }

    // MARK: - Move Gesture

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if case .idle = gestureState {
                    // Store the ORIGINAL coords for reference
                    gestureState = .moving(regionID: region.id, startRect: region.normalizedRect, offset: .zero)
                    onSelect()
                }

                if case .moving(let id, let startRect, _) = gestureState, id == region.id {
                    gestureState = .moving(regionID: id, startRect: startRect, offset: value.translation)
                }
            }
            .onEnded { value in
                if case .moving(let id, let startRect, let offset) = gestureState, id == region.id {
                    // Work in TRANSFORMED space
                    let transformedStartRect = startRect.applyingTransform(transform)
                    let dx = offset.width / converter.displayedSize.width
                    let dy = offset.height / converter.displayedSize.height
                    let newTransformedRect = transformedStartRect.offsetBy(dx: dx, dy: dy).clamped()
                    // onUpdate expects TRANSFORMED coords (parent will inverse-transform)
                    onUpdate(newTransformedRect)
                }
                gestureState = .idle
            }
    }
}

// MARK: - Grid Pattern Shape

/// A simple grid pattern shape for pixelate preview
struct GridPattern: Shape {
    let spacing: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let s = max(4, spacing)

        // Vertical lines
        var x: CGFloat = 0
        while x <= rect.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
            x += s
        }

        // Horizontal lines
        var y: CGFloat = 0
        while y <= rect.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
            y += s
        }

        return path
    }
}

struct DiagonalLinesPattern: Shape {
    let spacing: Double = 8

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let s = spacing

        // Diagonal lines from top-left to bottom-right
        var offset: CGFloat = -rect.height
        while offset <= rect.width {
            path.move(to: CGPoint(x: offset, y: 0))
            path.addLine(to: CGPoint(x: offset + rect.height, y: rect.height))
            offset += s
        }

        return path
    }
}

// MARK: - Blur Tool Settings Panel

/// Sidebar settings for blur tool
struct BlurToolSettingsPanel: View {
    @Environment(AppState.self) private var appState

    /// The currently selected region (if any)
    private var selectedRegion: BlurRegion? {
        appState.selectedBlurRegion
    }

    /// Current style - from selected region or default
    private var currentStyle: BlurRegion.BlurStyle {
        selectedRegion?.style ?? appState.blurStyle
    }

    /// Current intensity - from selected region or default
    private var currentIntensity: Double {
        selectedRegion?.intensity ?? appState.blurIntensity
    }

    var body: some View {
        @Bindable var state = appState

        VStack(alignment: .leading, spacing: 12) {
            // Style picker
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Style")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if selectedRegion != nil {
                        Spacer()
                        Text("(editing selected)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Picker("Style", selection: styleBinding) {
                    ForEach(BlurRegion.BlurStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Intensity slider (for blur and pixelate styles)
            if currentStyle == .blur || currentStyle == .pixelate {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Intensity")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(currentIntensity * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: intensityBinding, in: 0.0...1.0)
                }
            }

            Divider()

            // Region info and actions
            HStack {
                let regionCount = appState.activeImageBlurRegions.count
                Text("\(regionCount) region\(regionCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if regionCount > 0 {
                    Button("Clear All") {
                        appState.clearBlurRegions()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }

            // Apply to all images button
            if !appState.activeImageBlurRegions.isEmpty && appState.images.count > 1 {
                Button {
                    appState.applyBlurRegionsToAllImages()
                } label: {
                    Label("Apply to All Images", systemImage: "rectangle.stack")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Copy these blur regions to all other images")
            }

            // Instructions
            VStack(alignment: .leading, spacing: 4) {
                Text("Toggle drawing, then drag on canvas")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Press B to toggle drawing mode")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Bindings

    /// Binding for style - updates selected region or default
    private var styleBinding: Binding<BlurRegion.BlurStyle> {
        Binding(
            get: { currentStyle },
            set: { newStyle in
                if let regionID = selectedRegion?.id {
                    appState.updateBlurRegion(regionID, style: newStyle)
                } else {
                    appState.blurStyle = newStyle
                }
            }
        )
    }

    /// Binding for intensity - updates selected region or default
    private var intensityBinding: Binding<Double> {
        Binding(
            get: { currentIntensity },
            set: { newIntensity in
                if let regionID = selectedRegion?.id {
                    appState.updateBlurRegion(regionID, intensity: newIntensity)
                } else {
                    appState.blurIntensity = newIntensity
                }
            }
        )
    }
}
