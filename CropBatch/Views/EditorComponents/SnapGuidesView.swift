import SwiftUI

/// Displays snap guide lines based on detected rectangles
struct SnapGuidesView: View {
    let imageSize: CGSize
    let displayedSize: CGSize
    let snapPoints: SnapPoints
    let cropSettings: CropSettings
    var snapEnabled: Bool = true
    var snapThreshold: Int = 15
    var showDebug: Bool = false

    private var scale: CGFloat {
        displayedSize.width / imageSize.width
    }

    var body: some View {
        GeometryReader { geometry in
            if snapEnabled || showDebug {
                let offsetX = (geometry.size.width - displayedSize.width) / 2
                let offsetY = (geometry.size.height - displayedSize.height) / 2

                // Only show guides that are near current crop edges (within snap range)
                let cropTop = cropSettings.cropTop
                let cropBottom = Int(imageSize.height) - cropSettings.cropBottom
                let cropLeft = cropSettings.cropLeft
                let cropRight = Int(imageSize.width) - cropSettings.cropRight

                // Horizontal guide lines (for top/bottom edges)
                ForEach(snapPoints.horizontalEdges.filter { edge in
                    // In debug mode, show all; otherwise show if near a crop edge
                    showDebug || abs(edge - cropTop) <= snapThreshold + 5 || abs(edge - cropBottom) <= snapThreshold + 5
                }, id: \.self) { edge in
                    let y = offsetY + CGFloat(edge) * scale
                    let isSnapped = abs(edge - cropTop) <= 2 || abs(edge - (Int(imageSize.height) - cropSettings.cropBottom)) <= 2

                    Rectangle()
                        .fill(showDebug && !isSnapped ? Color.orange.opacity(0.5) : (isSnapped ? Color.green : Color.green.opacity(0.4)))
                        .frame(width: displayedSize.width, height: isSnapped ? 2 : 1)
                        .position(x: offsetX + displayedSize.width / 2, y: y)
                }

                // Vertical guide lines (for left/right edges)
                ForEach(snapPoints.verticalEdges.filter { edge in
                    // In debug mode, show all; otherwise show if near a crop edge
                    showDebug || abs(edge - cropLeft) <= snapThreshold + 5 || abs(edge - cropRight) <= snapThreshold + 5
                }, id: \.self) { edge in
                    let x = offsetX + CGFloat(edge) * scale
                    let isSnapped = abs(edge - cropLeft) <= 2 || abs(edge - (Int(imageSize.width) - cropSettings.cropRight)) <= 2

                    Rectangle()
                        .fill(showDebug && !isSnapped ? Color.orange.opacity(0.5) : (isSnapped ? Color.green : Color.green.opacity(0.4)))
                        .frame(width: isSnapped ? 2 : 1, height: displayedSize.height)
                        .position(x: x, y: offsetY + displayedSize.height / 2)
                }

                // Debug: show center cross if center snapping is implied
                if showDebug {
                    let centerX = Int(imageSize.width) / 2
                    let centerY = Int(imageSize.height) / 2
                    let isCenterHSnapped = snapPoints.horizontalEdges.contains(centerY)
                    let isCenterVSnapped = snapPoints.verticalEdges.contains(centerX)

                    if isCenterHSnapped {
                        Rectangle()
                            .fill(Color.blue.opacity(0.5))
                            .frame(width: displayedSize.width, height: 1)
                            .position(x: offsetX + displayedSize.width / 2, y: offsetY + CGFloat(centerY) * scale)
                    }
                    if isCenterVSnapped {
                        Rectangle()
                            .fill(Color.blue.opacity(0.5))
                            .frame(width: 1, height: displayedSize.height)
                            .position(x: offsetX + CGFloat(centerX) * scale, y: offsetY + displayedSize.height / 2)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
