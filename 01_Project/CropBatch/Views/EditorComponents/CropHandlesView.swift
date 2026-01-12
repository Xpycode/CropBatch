import SwiftUI

/// Displays draggable handles on crop edges and corners
struct CropHandlesView: View {
    let imageSize: CGSize
    let displayedSize: CGSize
    @Binding var cropSettings: CropSettings
    var snapPoints: SnapPoints = .empty
    var snapEnabled: Bool = true
    var snapThreshold: Int = 15  // Pixels threshold for snapping
    var onDragEnded: (() -> Void)? = nil

    private var scale: CGFloat {
        displayedSize.width / imageSize.width
    }

    /// Apply snapping to a value based on edge type
    private func applySnap(_ value: Int, edge: CropEdge, gridSnap: Bool, optionBypass: Bool) -> (value: Int, didSnap: Bool) {
        // Grid snapping takes priority (Control key)
        if gridSnap {
            return ((value / 10) * 10, true)
        }

        // Option key bypasses rectangle snapping
        if optionBypass { return (value, false) }

        // Rectangle snapping (only if enabled)
        guard snapEnabled else { return (value, false) }

        switch edge {
        case .top, .bottom:
            if let snapped = snapPoints.nearestHorizontalEdge(to: value, threshold: snapThreshold) {
                return (snapped, true)
            }
        case .left, .right:
            if let snapped = snapPoints.nearestVerticalEdge(to: value, threshold: snapThreshold) {
                return (snapped, true)
            }
        }

        return (value, false)
    }

    /// Check if a value is currently snapped to a rectangle edge
    private func isSnappedToRectangle(_ value: Int, edge: CropEdge) -> Bool {
        guard snapEnabled else { return false }

        switch edge {
        case .top, .bottom:
            return snapPoints.nearestHorizontalEdge(to: value, threshold: 2) != nil
        case .left, .right:
            return snapPoints.nearestVerticalEdge(to: value, threshold: 2) != nil
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let offsetX = (geometry.size.width - displayedSize.width) / 2
            let offsetY = (geometry.size.height - displayedSize.height) / 2

            // Calculate crop rectangle bounds for dynamic handle positioning
            let cropLeft = CGFloat(cropSettings.cropLeft) * scale
            let cropRight = CGFloat(cropSettings.cropRight) * scale
            let cropTop = CGFloat(cropSettings.cropTop) * scale
            let cropBottom = CGFloat(cropSettings.cropBottom) * scale
            let cropWidth = displayedSize.width - cropLeft - cropRight
            let cropHeight = displayedSize.height - cropTop - cropBottom

            // Center X for top/bottom handles (middle of visible crop line)
            let horizontalHandleCenterX = offsetX + cropLeft + cropWidth / 2
            // Center Y for left/right handles (middle of visible crop line)
            let verticalHandleCenterY = offsetY + cropTop + cropHeight / 2

            // Top handle with label
            handleWithLabel(
                edge: .top,
                value: cropSettings.cropTop,
                position: CGPoint(
                    x: horizontalHandleCenterX,
                    y: offsetY + cropTop
                ),
                labelOffset: CGPoint(x: 0, y: -25),
                onDrag: { location, gridSnapping, optionBypass in
                    let newY = location.y - offsetY
                    let rawValue = Int(newY / scale)
                    let (snappedValue, _) = applySnap(rawValue, edge: .top, gridSnap: gridSnapping, optionBypass: optionBypass)
                    cropSettings.cropTop = max(0, min(snappedValue, Int(imageSize.height) - cropSettings.cropBottom - 10))
                },
                onReset: { cropSettings.cropTop = 0 }
            )

            // Bottom handle with label
            handleWithLabel(
                edge: .bottom,
                value: cropSettings.cropBottom,
                position: CGPoint(
                    x: horizontalHandleCenterX,
                    y: offsetY + displayedSize.height - cropBottom
                ),
                labelOffset: CGPoint(x: 0, y: 25),
                onDrag: { location, gridSnapping, optionBypass in
                    let newY = location.y - offsetY
                    let fromBottom = displayedSize.height - newY
                    let rawValue = Int(fromBottom / scale)
                    let (snappedValue, _) = applySnap(rawValue, edge: .bottom, gridSnap: gridSnapping, optionBypass: optionBypass)
                    cropSettings.cropBottom = max(0, min(snappedValue, Int(imageSize.height) - cropSettings.cropTop - 10))
                },
                onReset: { cropSettings.cropBottom = 0 }
            )

            // Left handle with label
            handleWithLabel(
                edge: .left,
                value: cropSettings.cropLeft,
                position: CGPoint(
                    x: offsetX + cropLeft,
                    y: verticalHandleCenterY
                ),
                labelOffset: CGPoint(x: -30, y: 0),
                onDrag: { location, gridSnapping, optionBypass in
                    let newX = location.x - offsetX
                    let rawValue = Int(newX / scale)
                    let (snappedValue, _) = applySnap(rawValue, edge: .left, gridSnap: gridSnapping, optionBypass: optionBypass)
                    cropSettings.cropLeft = max(0, min(snappedValue, Int(imageSize.width) - cropSettings.cropRight - 10))
                },
                onReset: { cropSettings.cropLeft = 0 }
            )

            // Right handle with label
            handleWithLabel(
                edge: .right,
                value: cropSettings.cropRight,
                position: CGPoint(
                    x: offsetX + displayedSize.width - cropRight,
                    y: verticalHandleCenterY
                ),
                labelOffset: CGPoint(x: 30, y: 0),
                onDrag: { location, gridSnapping, optionBypass in
                    let newX = location.x - offsetX
                    let fromRight = displayedSize.width - newX
                    let rawValue = Int(fromRight / scale)
                    let (snappedValue, _) = applySnap(rawValue, edge: .right, gridSnap: gridSnapping, optionBypass: optionBypass)
                    cropSettings.cropRight = max(0, min(snappedValue, Int(imageSize.width) - cropSettings.cropLeft - 10))
                },
                onReset: { cropSettings.cropRight = 0 }
            )

            // MARK: Corner Handles

            // Top-Left corner
            CornerHandle(corner: .topLeft, isSnapping: NSEvent.modifierFlags.contains(.control))
                .position(
                    x: offsetX + CGFloat(cropSettings.cropLeft) * scale,
                    y: offsetY + CGFloat(cropSettings.cropTop) * scale
                )
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            let gridSnapping = NSEvent.modifierFlags.contains(.control)
                            let optionBypass = NSEvent.modifierFlags.contains(.option)
                            let newX = gesture.location.x - offsetX
                            let newY = gesture.location.y - offsetY
                            let rawTop = Int(newY / scale)
                            let rawLeft = Int(newX / scale)
                            let (topValue, _) = applySnap(rawTop, edge: .top, gridSnap: gridSnapping, optionBypass: optionBypass)
                            let (leftValue, _) = applySnap(rawLeft, edge: .left, gridSnap: gridSnapping, optionBypass: optionBypass)
                            cropSettings.cropTop = max(0, min(topValue, Int(imageSize.height) - cropSettings.cropBottom - 10))
                            cropSettings.cropLeft = max(0, min(leftValue, Int(imageSize.width) - cropSettings.cropRight - 10))
                        }
                        .onEnded { _ in onDragEnded?() }
                )
                .onTapGesture(count: 2) {
                    cropSettings.cropTop = 0
                    cropSettings.cropLeft = 0
                    onDragEnded?()
                }

            // Top-Right corner
            CornerHandle(corner: .topRight, isSnapping: NSEvent.modifierFlags.contains(.control))
                .position(
                    x: offsetX + displayedSize.width - CGFloat(cropSettings.cropRight) * scale,
                    y: offsetY + CGFloat(cropSettings.cropTop) * scale
                )
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            let gridSnapping = NSEvent.modifierFlags.contains(.control)
                            let optionBypass = NSEvent.modifierFlags.contains(.option)
                            let newX = gesture.location.x - offsetX
                            let newY = gesture.location.y - offsetY
                            let fromRight = displayedSize.width - newX
                            let rawTop = Int(newY / scale)
                            let rawRight = Int(fromRight / scale)
                            let (topValue, _) = applySnap(rawTop, edge: .top, gridSnap: gridSnapping, optionBypass: optionBypass)
                            let (rightValue, _) = applySnap(rawRight, edge: .right, gridSnap: gridSnapping, optionBypass: optionBypass)
                            cropSettings.cropTop = max(0, min(topValue, Int(imageSize.height) - cropSettings.cropBottom - 10))
                            cropSettings.cropRight = max(0, min(rightValue, Int(imageSize.width) - cropSettings.cropLeft - 10))
                        }
                        .onEnded { _ in onDragEnded?() }
                )
                .onTapGesture(count: 2) {
                    cropSettings.cropTop = 0
                    cropSettings.cropRight = 0
                    onDragEnded?()
                }

            // Bottom-Left corner
            CornerHandle(corner: .bottomLeft, isSnapping: NSEvent.modifierFlags.contains(.control))
                .position(
                    x: offsetX + CGFloat(cropSettings.cropLeft) * scale,
                    y: offsetY + displayedSize.height - CGFloat(cropSettings.cropBottom) * scale
                )
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            let gridSnapping = NSEvent.modifierFlags.contains(.control)
                            let optionBypass = NSEvent.modifierFlags.contains(.option)
                            let newX = gesture.location.x - offsetX
                            let newY = gesture.location.y - offsetY
                            let fromBottom = displayedSize.height - newY
                            let rawBottom = Int(fromBottom / scale)
                            let rawLeft = Int(newX / scale)
                            let (bottomValue, _) = applySnap(rawBottom, edge: .bottom, gridSnap: gridSnapping, optionBypass: optionBypass)
                            let (leftValue, _) = applySnap(rawLeft, edge: .left, gridSnap: gridSnapping, optionBypass: optionBypass)
                            cropSettings.cropBottom = max(0, min(bottomValue, Int(imageSize.height) - cropSettings.cropTop - 10))
                            cropSettings.cropLeft = max(0, min(leftValue, Int(imageSize.width) - cropSettings.cropRight - 10))
                        }
                        .onEnded { _ in onDragEnded?() }
                )
                .onTapGesture(count: 2) {
                    cropSettings.cropBottom = 0
                    cropSettings.cropLeft = 0
                    onDragEnded?()
                }

            // Bottom-Right corner
            CornerHandle(corner: .bottomRight, isSnapping: NSEvent.modifierFlags.contains(.control))
                .position(
                    x: offsetX + displayedSize.width - CGFloat(cropSettings.cropRight) * scale,
                    y: offsetY + displayedSize.height - CGFloat(cropSettings.cropBottom) * scale
                )
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            let gridSnapping = NSEvent.modifierFlags.contains(.control)
                            let optionBypass = NSEvent.modifierFlags.contains(.option)
                            let newX = gesture.location.x - offsetX
                            let newY = gesture.location.y - offsetY
                            let fromRight = displayedSize.width - newX
                            let fromBottom = displayedSize.height - newY
                            let rawBottom = Int(fromBottom / scale)
                            let rawRight = Int(fromRight / scale)
                            let (bottomValue, _) = applySnap(rawBottom, edge: .bottom, gridSnap: gridSnapping, optionBypass: optionBypass)
                            let (rightValue, _) = applySnap(rawRight, edge: .right, gridSnap: gridSnapping, optionBypass: optionBypass)
                            cropSettings.cropBottom = max(0, min(bottomValue, Int(imageSize.height) - cropSettings.cropTop - 10))
                            cropSettings.cropRight = max(0, min(rightValue, Int(imageSize.width) - cropSettings.cropLeft - 10))
                        }
                        .onEnded { _ in onDragEnded?() }
                )
                .onTapGesture(count: 2) {
                    cropSettings.cropBottom = 0
                    cropSettings.cropRight = 0
                    onDragEnded?()
                }
        }
    }

    @ViewBuilder
    private func handleWithLabel(
        edge: CropEdge,
        value: Int,
        position: CGPoint,
        labelOffset: CGPoint,
        onDrag: @escaping (CGPoint, Bool, Bool) -> Void,  // (location, gridSnap, optionBypass)
        onReset: @escaping () -> Void
    ) -> some View {
        let isGridSnapping = NSEvent.modifierFlags.contains(.control)
        let isOptionHeld = NSEvent.modifierFlags.contains(.option)
        let isRectSnapped = !isOptionHeld && isSnappedToRectangle(value, edge: edge)

        ZStack {
            EdgeHandle(
                edge: edge,
                value: value,
                isSnapping: isGridSnapping,
                isRectangleSnapping: isRectSnapped
            )
                .position(position)
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            let gridSnap = NSEvent.modifierFlags.contains(.control)
                            let optionBypass = NSEvent.modifierFlags.contains(.option)
                            onDrag(gesture.location, gridSnap, optionBypass)
                        }
                        .onEnded { _ in
                            onDragEnded?()
                        }
                )
                .onTapGesture(count: 2) {
                    onReset()
                    onDragEnded?()
                }

            // Pixel label (only show if value > 0)
            if value > 0 {
                PixelLabel(
                    value: value,
                    isSnapping: isGridSnapping,
                    isRectangleSnapping: isRectSnapped
                )
                    .position(x: position.x + labelOffset.x, y: position.y + labelOffset.y)
            }
        }
    }
}

// MARK: - Edge Handle

struct EdgeHandle: View {
    let edge: CropEdge
    let value: Int
    let isSnapping: Bool  // Grid snapping (Control key)
    var isRectangleSnapping: Bool = false  // Snapped to detected rectangle edge

    private var isVertical: Bool {
        edge == .left || edge == .right
    }

    private var fillColor: Color {
        if isSnapping {
            return .orange  // Grid snap
        } else if isRectangleSnapping {
            return .green  // Rectangle snap
        } else {
            return .accentColor
        }
    }

    var body: some View {
        ZStack {
            Capsule()
                .fill(fillColor)
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
        .shadow(color: isRectangleSnapping ? .green.opacity(0.5) : .black.opacity(0.3), radius: isRectangleSnapping ? 4 : 2, x: 0, y: 1)
        .contentShape(Rectangle().size(width: 44, height: 44))
        .cursor(isVertical ? .resizeLeftRight : .resizeUpDown)
        .accessibilityLabel("\(edge.rawValue.capitalized) crop handle")
        .accessibilityValue("\(value) pixels")
        .accessibilityHint("Drag to adjust \(edge.rawValue) crop. Double-tap to reset.")
    }
}

// MARK: - Corner Handle

struct CornerHandle: View {
    let corner: Corner
    let isSnapping: Bool

    enum Corner: String {
        case topLeft = "top-left"
        case topRight = "top-right"
        case bottomLeft = "bottom-left"
        case bottomRight = "bottom-right"
    }

    var body: some View {
        Circle()
            .fill(isSnapping ? Color.orange : Color.accentColor)
            .frame(width: 14, height: 14)
            .overlay(
                Circle()
                    .fill(Color.white)
                    .frame(width: 6, height: 6)
            )
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            .contentShape(Rectangle().size(width: 30, height: 30))
            .accessibilityLabel("\(corner.rawValue) corner handle")
            .accessibilityHint("Drag to adjust crop from \(corner.rawValue) corner. Double-tap to reset.")
            .cursor(.crosshair)
    }
}

// MARK: - Pixel Label

struct PixelLabel: View {
    let value: Int
    let isSnapping: Bool  // Grid snapping
    var isRectangleSnapping: Bool = false  // Rectangle snapping

    private var fillColor: Color {
        if isSnapping {
            return .orange
        } else if isRectangleSnapping {
            return .green
        } else {
            return .accentColor
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            if isRectangleSnapping {
                Image(systemName: "rectangle.inset.filled")
                    .font(.system(size: 9))
            }
            Text("\(value)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(fillColor)
        )
        .shadow(color: isRectangleSnapping ? .green.opacity(0.4) : .black.opacity(0.2), radius: isRectangleSnapping ? 4 : 2, x: 0, y: 1)
        .accessibilityHidden(true)  // Value is already announced by EdgeHandle
    }
}
