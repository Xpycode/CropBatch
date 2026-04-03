import SwiftUI

// MARK: - Compact Crop Field

struct CompactCropField: View {
    let label: String
    @Binding var value: Int
    var onCommit: (() -> Void)?

    @State private var isDragging = false
    @State private var isHovering = false
    @State private var dragStartValue: Int = 0

    // Sensitivity: points of drag per 1px value change
    private let dragSensitivity: CGFloat = 2.0

    var body: some View {
        HStack(spacing: 4) {
            // Draggable label with always-visible styling
            HStack(spacing: 2) {
                // Drag indicator chevrons
                Image(systemName: "chevron.left")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(isDragging ? .primary : .tertiary)

                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isDragging ? .primary : (isHovering ? .primary : .secondary))
                    .lineLimit(1)
                    .fixedSize()

                Image(systemName: "chevron.right")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(isDragging ? .primary : .tertiary)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isDragging ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isDragging ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else if !isDragging {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            dragStartValue = value
                        }
                        let delta = Int(gesture.translation.width / dragSensitivity)
                        value = max(0, dragStartValue + delta)
                    }
                    .onEnded { _ in
                        isDragging = false
                        if !isHovering {
                            NSCursor.pop()
                        }
                        onCommit?()
                    }
            )
            .help("Drag left/right to adjust value")

            TextField("", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 46)
                .font(.system(size: 11, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .onSubmit { onCommit?() }
        }
    }
}
