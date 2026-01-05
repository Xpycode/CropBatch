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
