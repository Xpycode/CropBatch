import SwiftUI

/// Displays a preview of where the watermark will appear on export
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
                .cursor(.openHand)
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
            .cursor(.openHand)
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
