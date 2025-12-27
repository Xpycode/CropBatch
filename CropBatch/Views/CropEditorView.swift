import SwiftUI

struct CropEditorView: View {
    @Environment(AppState.self) private var appState
    let image: ImageItem

    @State private var imageFrame: CGRect = .zero
    @FocusState private var isFocused: Bool

    var body: some View {
        editorContent
            .focusable()
            .focused($isFocused)
            .onAppear { isFocused = true }
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], phases: .down) { keyPress in
                handleKeyPress(keyPress)
            }
    }

    private var editorContent: some View {
        GeometryReader { geometry in
            ZStack {
                Color(nsColor: .controlBackgroundColor)
                imageWithOverlays
                    .padding(40)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private var imageWithOverlays: some View {
        Image(nsImage: image.originalImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .overlay { cropOverlay }
            .overlay { cropHandles }
            .background { frameMeasurer }
    }

    private var cropOverlay: some View {
        CropOverlayView(
            imageSize: image.originalSize,
            displayedSize: displayedImageSize,
            cropSettings: appState.cropSettings
        )
    }

    private var cropHandles: some View {
        CropHandlesView(
            imageSize: image.originalSize,
            displayedSize: displayedImageSize,
            cropSettings: Binding(
                get: { appState.cropSettings },
                set: { appState.cropSettings = $0 }
            )
        )
    }

    private var frameMeasurer: some View {
        GeometryReader { imageGeometry in
            Color.clear
                .onAppear {
                    imageFrame = imageGeometry.frame(in: .local)
                }
                .onChange(of: imageGeometry.size) { _, newSize in
                    imageFrame = CGRect(origin: .zero, size: newSize)
                }
        }
    }

    private var scale: CGFloat {
        guard imageFrame.width > 0, imageFrame.height > 0 else { return 1 }
        let scaleX = imageFrame.width / image.originalSize.width
        let scaleY = imageFrame.height / image.originalSize.height
        return min(scaleX, scaleY)
    }

    private var displayedImageSize: CGSize {
        CGSize(
            width: image.originalSize.width * scale,
            height: image.originalSize.height * scale
        )
    }

    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        let hasShift = keyPress.modifiers.contains(.shift)
        let hasControl = keyPress.modifiers.contains(.control)
        let delta = hasControl ? 10 : 1

        if hasShift {
            // Crop adjustment mode
            switch keyPress.key {
            case .upArrow:
                appState.adjustCrop(edge: .top, delta: delta)
                return .handled
            case .downArrow:
                appState.adjustCrop(edge: .bottom, delta: delta)
                return .handled
            case .leftArrow:
                appState.adjustCrop(edge: .left, delta: delta)
                return .handled
            case .rightArrow:
                appState.adjustCrop(edge: .right, delta: delta)
                return .handled
            default:
                return .ignored
            }
        } else {
            // Navigation mode (no modifiers)
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
        // Top
        Rectangle()
            .fill(Color.black.opacity(0.5))
            .frame(width: displayedSize.width, height: CGFloat(cropSettings.cropTop) * scale)
            .position(
                x: offsetX + displayedSize.width / 2,
                y: offsetY + CGFloat(cropSettings.cropTop) * scale / 2
            )

        // Bottom
        Rectangle()
            .fill(Color.black.opacity(0.5))
            .frame(width: displayedSize.width, height: CGFloat(cropSettings.cropBottom) * scale)
            .position(
                x: offsetX + displayedSize.width / 2,
                y: offsetY + displayedSize.height - CGFloat(cropSettings.cropBottom) * scale / 2
            )

        // Left
        Rectangle()
            .fill(Color.black.opacity(0.5))
            .frame(
                width: CGFloat(cropSettings.cropLeft) * scale,
                height: displayedSize.height - CGFloat(cropSettings.cropTop + cropSettings.cropBottom) * scale
            )
            .position(
                x: offsetX + CGFloat(cropSettings.cropLeft) * scale / 2,
                y: offsetY + displayedSize.height / 2
            )

        // Right
        Rectangle()
            .fill(Color.black.opacity(0.5))
            .frame(
                width: CGFloat(cropSettings.cropRight) * scale,
                height: displayedSize.height - CGFloat(cropSettings.cropTop + cropSettings.cropBottom) * scale
            )
            .position(
                x: offsetX + displayedSize.width - CGFloat(cropSettings.cropRight) * scale / 2,
                y: offsetY + displayedSize.height / 2
            )
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

            topHandle(offsetX: offsetX, offsetY: offsetY)
            bottomHandle(offsetX: offsetX, offsetY: offsetY)
            leftHandle(offsetX: offsetX, offsetY: offsetY)
            rightHandle(offsetX: offsetX, offsetY: offsetY)
        }
    }

    private func topHandle(offsetX: CGFloat, offsetY: CGFloat) -> some View {
        EdgeHandle(edge: .top)
            .position(
                x: offsetX + displayedSize.width / 2,
                y: offsetY + CGFloat(cropSettings.cropTop) * scale
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let newY = value.location.y - offsetY
                        let pixelValue = Int(newY / scale)
                        cropSettings.cropTop = max(0, min(pixelValue, Int(imageSize.height) - cropSettings.cropBottom - 10))
                    }
            )
    }

    private func bottomHandle(offsetX: CGFloat, offsetY: CGFloat) -> some View {
        EdgeHandle(edge: .bottom)
            .position(
                x: offsetX + displayedSize.width / 2,
                y: offsetY + displayedSize.height - CGFloat(cropSettings.cropBottom) * scale
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let newY = value.location.y - offsetY
                        let fromBottom = displayedSize.height - newY
                        let pixelValue = Int(fromBottom / scale)
                        cropSettings.cropBottom = max(0, min(pixelValue, Int(imageSize.height) - cropSettings.cropTop - 10))
                    }
            )
    }

    private func leftHandle(offsetX: CGFloat, offsetY: CGFloat) -> some View {
        EdgeHandle(edge: .left)
            .position(
                x: offsetX + CGFloat(cropSettings.cropLeft) * scale,
                y: offsetY + displayedSize.height / 2
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let newX = value.location.x - offsetX
                        let pixelValue = Int(newX / scale)
                        cropSettings.cropLeft = max(0, min(pixelValue, Int(imageSize.width) - cropSettings.cropRight - 10))
                    }
            )
    }

    private func rightHandle(offsetX: CGFloat, offsetY: CGFloat) -> some View {
        EdgeHandle(edge: .right)
            .position(
                x: offsetX + displayedSize.width - CGFloat(cropSettings.cropRight) * scale,
                y: offsetY + displayedSize.height / 2
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let newX = value.location.x - offsetX
                        let fromRight = displayedSize.width - newX
                        let pixelValue = Int(fromRight / scale)
                        cropSettings.cropRight = max(0, min(pixelValue, Int(imageSize.width) - cropSettings.cropLeft - 10))
                    }
            )
    }
}

struct EdgeHandle: View {
    let edge: CropEdge

    private var isVertical: Bool {
        edge == .left || edge == .right
    }

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.accentColor)
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
