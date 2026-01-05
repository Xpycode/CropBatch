import SwiftUI

/// Displays an aspect ratio guide overlay within the crop area
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
        .accessibilityHidden(true)
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
