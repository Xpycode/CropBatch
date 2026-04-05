import SwiftUI

struct KeyboardShortcutsContentView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left column: Navigation & Crop
            VStack(alignment: .leading, spacing: 4) {
                Text("Navigation & Crop")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 2)

                ShortcutRow(keys: "←  →", description: "Navigate")
                ShortcutRow(keys: "⇧ Arrow", description: "Adjust crop")
                ShortcutRow(keys: "⇧⌥ Arrow", description: "Uncrop")
                ShortcutRow(keys: "⇧⌃ Arrow", description: "×10 adjust")
                ShortcutRow(keys: "⌃ Drag", description: "Snap grid")
                ShortcutRow(keys: "⌥ Drag", description: "Bypass snap")
                ShortcutRow(keys: "B", description: "Toggle blur draw")
                ShortcutRow(keys: "S", description: "Toggle snap")
                ShortcutRow(keys: "Dbl-click", description: "Reset")
            }
            .frame(width: 190, alignment: .leading)

            Divider()
                .padding(.horizontal, 8)

            // Right column: Zoom
            VStack(alignment: .leading, spacing: 4) {
                Text("Zoom")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 2)

                ZoomShortcutRow(keys: "⌘1", description: "100%")
                ZoomShortcutRow(keys: "⌘2", description: "Fit")
                ZoomShortcutRow(keys: "⌘3", description: "Width")
                ZoomShortcutRow(keys: "⌘4", description: "Height")
            }

            Spacer()
        }
    }
}

struct ShortcutRow: View {
    let keys: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Text(keys)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: 70, alignment: .leading)

            Text(description)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct ZoomShortcutRow: View {
    let keys: String
    let description: String

    var body: some View {
        HStack(spacing: 10) {
            Text(keys)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: 24, alignment: .leading)

            Text(description)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}
