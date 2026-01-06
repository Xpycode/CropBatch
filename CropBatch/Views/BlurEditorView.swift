import SwiftUI
import Combine

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

    @State private var gestureState: BlurGestureState = .idle
    @State private var converter: CoordinateConverter?

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
        .onAppear { converter = currentConverter }
        .onChange(of: displayedSize) { _, _ in converter = currentConverter }
    }

    // MARK: - Drawing Layer

    @ViewBuilder
    private func drawingLayer(converter: CoordinateConverter) -> some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .onTapGesture {
                appState.selectBlurRegion(nil)
            }
            .gesture(drawingGesture(converter: converter))
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
            // Live blur preview - show the image portion with blur applied
            GeometryReader { geo in
                Image(nsImage: displayedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: converter.displayedSize.width, height: converter.displayedSize.height)
                    .blur(radius: 30 * region.intensity)
                    .offset(x: -displayRect.minX, y: -displayRect.minY)
            }
            .frame(width: displayRect.width, height: displayRect.height)
            .clipped()

        case .pixelate:
            // Pixelate preview - mosaic effect indicator
            ZStack {
                Color.purple.opacity(0.2)
                GridPattern(spacing: max(4, 12 * (1 - region.intensity)))
                    .stroke(Color.purple.opacity(0.4), lineWidth: 1)
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

// MARK: - Blur Regions Crop Preview

/// Shows blur regions as outlines when in crop mode (read-only preview)
struct BlurRegionsCropPreview: View {
    @Environment(AppState.self) private var appState

    /// Original image size (pre-transform)
    let originalImageSize: CGSize

    /// Displayed size on screen
    let displayedSize: CGSize

    /// Current transform
    let transform: ImageTransform

    /// Transformed image size (accounts for rotation)
    private var transformedImageSize: CGSize {
        transform.transformedSize(originalImageSize)
    }

    var body: some View {
        let converter = CoordinateConverter(
            imageSize: transformedImageSize,
            displayedSize: displayedSize,
            displayOffset: .zero
        )

        ZStack {
            ForEach(appState.activeImageBlurRegions) { region in
                // Crop calculations use ORIGINAL coords
                let isOutside = region.isOutsideCrop(appState.cropSettings, imageSize: originalImageSize)
                let isPartial = region.isPartiallyCropped(appState.cropSettings, imageSize: originalImageSize)
                // Display uses TRANSFORMED coords
                let transformedRect = region.normalizedRect.applyingTransform(transform)
                let displayRect = converter.normalizedToView(transformedRect)

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

                // Note: Pixelate hidden until live preview is implemented (see future-features.md)
                Picker("Style", selection: styleBinding) {
                    ForEach(BlurRegion.BlurStyle.allCases.filter { $0 != .pixelate }) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Intensity slider (for blur style)
            if currentStyle == .blur {
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
                Text("Draw rectangles to add blur regions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Press B to toggle blur mode")
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
