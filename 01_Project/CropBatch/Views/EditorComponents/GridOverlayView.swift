import SwiftUI

/// Displays dashed grid lines on the crop preview when grid split is enabled
struct GridOverlayView: View {
    let imageSize: CGSize
    let displayedSize: CGSize
    let cropSettings: CropSettings
    let gridSettings: GridSettings

    private var scale: CGFloat {
        displayedSize.width / imageSize.width
    }

    var body: some View {
        if gridSettings.isEnabled && (gridSettings.rows > 1 || gridSettings.columns > 1) {
            GeometryReader { geometry in
                let offsetX = (geometry.size.width - displayedSize.width) / 2
                let offsetY = (geometry.size.height - displayedSize.height) / 2

                let cropX = offsetX + CGFloat(cropSettings.cropLeft) * scale
                let cropY = offsetY + CGFloat(cropSettings.cropTop) * scale
                let cropWidth = displayedSize.width - CGFloat(cropSettings.cropLeft + cropSettings.cropRight) * scale
                let cropHeight = displayedSize.height - CGFloat(cropSettings.cropTop + cropSettings.cropBottom) * scale

                Path { path in
                    let cols = gridSettings.columns
                    let rows = gridSettings.rows

                    // Vertical lines (between columns)
                    for col in 1..<cols {
                        let x = cropX + cropWidth * CGFloat(col) / CGFloat(cols)
                        path.move(to: CGPoint(x: x, y: cropY))
                        path.addLine(to: CGPoint(x: x, y: cropY + cropHeight))
                    }

                    // Horizontal lines (between rows)
                    for row in 1..<rows {
                        let y = cropY + cropHeight * CGFloat(row) / CGFloat(rows)
                        path.move(to: CGPoint(x: cropX, y: y))
                        path.addLine(to: CGPoint(x: cropX + cropWidth, y: y))
                    }
                }
                .stroke(
                    Color.yellow.opacity(0.6),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
            }
            .allowsHitTesting(false)
        }
    }
}
