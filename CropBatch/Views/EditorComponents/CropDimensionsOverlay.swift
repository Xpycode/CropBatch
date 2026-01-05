import SwiftUI

/// Displays the crop dimensions label and allows drag-to-move the crop window
struct CropDimensionsOverlay: View {
    let imageSize: CGSize
    let displayedSize: CGSize
    @Binding var cropSettings: CropSettings
    var onDragEnded: (() -> Void)? = nil

    @State private var isDragging = false
    @State private var isHovering = false
    @State private var cursorPushed = false  // Track cursor state for cleanup
    // Store initial crop values at drag start (DragGesture gives cumulative translation)
    @State private var dragStartCrop: (left: Int, right: Int, top: Int, bottom: Int)?

    private var scale: CGFloat {
        displayedSize.width / imageSize.width
    }

    private var outputSize: CGSize {
        cropSettings.croppedSize(from: imageSize)
    }

    /// Whether the crop can be moved (has room to slide in any direction)
    private var canMove: Bool {
        cropSettings.hasAnyCrop && (
            cropSettings.cropLeft > 0 || cropSettings.cropRight > 0 ||
            cropSettings.cropTop > 0 || cropSettings.cropBottom > 0
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let offsetX = (geometry.size.width - displayedSize.width) / 2
            let offsetY = (geometry.size.height - displayedSize.height) / 2

            let cropRect = CGRect(
                x: offsetX + CGFloat(cropSettings.cropLeft) * scale,
                y: offsetY + CGFloat(cropSettings.cropTop) * scale,
                width: displayedSize.width - CGFloat(cropSettings.cropLeft + cropSettings.cropRight) * scale,
                height: displayedSize.height - CGFloat(cropSettings.cropTop + cropSettings.cropBottom) * scale
            )

            if cropSettings.hasAnyCrop {
                HStack(spacing: 6) {
                    // Move icon hint
                    if canMove && (isHovering || isDragging) {
                        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Text("\(Int(outputSize.width)) × \(Int(outputSize.height))")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isDragging ? Color.accentColor.opacity(0.8) : Color.black.opacity(0.6))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(isHovering && canMove ? Color.white.opacity(0.5) : Color.clear, lineWidth: 1)
                )
                .position(x: cropRect.midX, y: cropRect.midY)
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            // Capture initial values at drag start
                            if dragStartCrop == nil {
                                dragStartCrop = (
                                    cropSettings.cropLeft,
                                    cropSettings.cropRight,
                                    cropSettings.cropTop,
                                    cropSettings.cropBottom
                                )
                            }
                            isDragging = true
                            handleDrag(translation: gesture.translation)
                        }
                        .onEnded { _ in
                            isDragging = false
                            dragStartCrop = nil
                            onDragEnded?()
                        }
                )
                .onHover { hovering in
                    isHovering = hovering
                    if hovering && canMove {
                        if !cursorPushed {
                            NSCursor.openHand.push()
                            cursorPushed = true
                        }
                    } else if cursorPushed {
                        NSCursor.pop()
                        cursorPushed = false
                    }
                }
                .onChange(of: isDragging) { _, dragging in
                    if dragging && canMove {
                        if cursorPushed {
                            NSCursor.pop()
                        }
                        NSCursor.closedHand.push()
                        cursorPushed = true
                    } else if !dragging {
                        if cursorPushed {
                            NSCursor.pop()
                            cursorPushed = false
                        }
                        if isHovering && canMove {
                            NSCursor.openHand.push()
                            cursorPushed = true
                        }
                    }
                }
                .onDisappear {
                    if cursorPushed {
                        NSCursor.pop()
                        cursorPushed = false
                    }
                }
                .accessibilityLabel("Crop dimensions")
                .accessibilityValue("\(Int(outputSize.width)) by \(Int(outputSize.height)) pixels")
                .accessibilityHint("Drag to move the crop window")
            }
        }
    }

    /// Handle drag to move the crop window
    private func handleDrag(translation: CGSize) {
        guard let start = dragStartCrop else { return }

        // Convert screen translation to pixel values
        let deltaX = Int(translation.width / scale)
        let deltaY = Int(translation.height / scale)

        // Calculate new values based on initial + delta
        var newLeft = start.left + deltaX
        var newRight = start.right - deltaX
        var newTop = start.top + deltaY
        var newBottom = start.bottom - deltaY

        // Clamp to valid range (can't go negative)
        if newLeft < 0 {
            newRight += newLeft  // Shift excess back
            newLeft = 0
        }
        if newRight < 0 {
            newLeft += newRight
            newRight = 0
        }
        if newTop < 0 {
            newBottom += newTop
            newTop = 0
        }
        if newBottom < 0 {
            newTop += newBottom
            newBottom = 0
        }

        // Apply clamped values
        cropSettings.cropLeft = max(0, newLeft)
        cropSettings.cropRight = max(0, newRight)
        cropSettings.cropTop = max(0, newTop)
        cropSettings.cropBottom = max(0, newBottom)
    }
}
