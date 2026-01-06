import SwiftUI

/// Displays the semi-transparent crop overlay with darkened regions
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
                if cropSettings.cornerRadiusEnabled {
                    cornerMasks(offsetX: offsetX, offsetY: offsetY)
                }
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
    private func cornerMasks(offsetX: CGFloat, offsetY: CGFloat) -> some View {
        let cropRect = CGRect(
            x: offsetX + CGFloat(cropSettings.cropLeft) * scale,
            y: offsetY + CGFloat(cropSettings.cropTop) * scale,
            width: displayedSize.width - CGFloat(cropSettings.cropLeft + cropSettings.cropRight) * scale,
            height: displayedSize.height - CGFloat(cropSettings.cropTop + cropSettings.cropBottom) * scale
        )

        // Get scaled corner radii
        if let radii = cropSettings.effectiveCornerRadii(for: cropRect.size) {
            let scaledRadii = RectangleCornerRadii(
                topLeading: radii.topLeading * scale,
                bottomLeading: radii.bottomLeading * scale,
                bottomTrailing: radii.bottomTrailing * scale,
                topTrailing: radii.topTrailing * scale
            )

            // Draw corner masks using a checkerboard pattern to indicate transparency
            Canvas { context, size in
                // Create the rectangular crop area
                let rect = cropRect

                // Create a rounded rectangle path
                let roundedPath = Path(roundedRect: rect, cornerRadii: scaledRadii, style: .continuous)

                // Create corner rectangles and subtract the rounded path to show only corners
                // Top-left corner
                let tlRect = CGRect(x: rect.minX, y: rect.minY, width: scaledRadii.topLeading, height: scaledRadii.topLeading)
                // Top-right corner
                let trRect = CGRect(x: rect.maxX - scaledRadii.topTrailing, y: rect.minY, width: scaledRadii.topTrailing, height: scaledRadii.topTrailing)
                // Bottom-left corner
                let blRect = CGRect(x: rect.minX, y: rect.maxY - scaledRadii.bottomLeading, width: scaledRadii.bottomLeading, height: scaledRadii.bottomLeading)
                // Bottom-right corner
                let brRect = CGRect(x: rect.maxX - scaledRadii.bottomTrailing, y: rect.maxY - scaledRadii.bottomTrailing, width: scaledRadii.bottomTrailing, height: scaledRadii.bottomTrailing)

                // Fill corners with semi-transparent overlay (will be transparent in output)
                for cornerRect in [tlRect, trRect, blRect, brRect] {
                    let cornerPath = Path(cornerRect)
                    // We want to show what's OUTSIDE the rounded rect but INSIDE the corner squares
                    context.fill(cornerPath, with: .color(.black.opacity(0.5)))
                }

                // Then "cut out" the rounded rect area from the corners
                context.blendMode = .destinationOut
                context.fill(roundedPath, with: .color(.white))
            }
        }
    }

    @ViewBuilder
    private func cropBorder(offsetX: CGFloat, offsetY: CGFloat) -> some View {
        let cropRect = CGRect(
            x: offsetX + CGFloat(cropSettings.cropLeft) * scale,
            y: offsetY + CGFloat(cropSettings.cropTop) * scale,
            width: displayedSize.width - CGFloat(cropSettings.cropLeft + cropSettings.cropRight) * scale,
            height: displayedSize.height - CGFloat(cropSettings.cropTop + cropSettings.cropBottom) * scale
        )

        if cropSettings.cornerRadiusEnabled,
           let radii = cropSettings.effectiveCornerRadii(for: cropRect.size) {
            let scaledRadii = RectangleCornerRadii(
                topLeading: radii.topLeading * scale,
                bottomLeading: radii.bottomLeading * scale,
                bottomTrailing: radii.bottomTrailing * scale,
                topTrailing: radii.topTrailing * scale
            )

            UnevenRoundedRectangle(cornerRadii: scaledRadii, style: .continuous)
                .strokeBorder(Color.white, lineWidth: 2)
                .frame(width: cropRect.width, height: cropRect.height)
                .position(x: cropRect.midX, y: cropRect.midY)
        } else {
            Rectangle()
                .strokeBorder(Color.white, lineWidth: 2)
                .frame(width: cropRect.width, height: cropRect.height)
                .position(x: cropRect.midX, y: cropRect.midY)
        }
    }
}
