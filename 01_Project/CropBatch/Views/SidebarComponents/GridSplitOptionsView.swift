import SwiftUI

// MARK: - Grid Split Options (Content only, toggle in header)

struct GridSplitOptionsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        let columns = appState.exportSettings.gridSettings.columns
        let rows = appState.exportSettings.gridSettings.rows
        let tileCount = columns * rows

        // Compute approximate tile size from first image's post-crop size
        let tileSize: CGSize? = {
            guard let imageSize = appState.activeImage?.originalSize else { return nil }
            let cropped = appState.cropSettings.croppedSize(from: imageSize)
            guard cropped.width > 0, cropped.height > 0 else { return nil }
            return CGSize(
                width: cropped.width / CGFloat(columns),
                height: cropped.height / CGFloat(rows)
            )
        }()

        Stepper(value: $state.exportSettings.gridSettings.columns, in: 1...10) {
            LabeledContent("Columns") {
                Text("\(columns)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: appState.exportSettings.gridSettings.columns) { oldValue, newValue in
            // Square shortcut: if rows matched columns before, keep them matched
            if appState.exportSettings.gridSettings.rows == oldValue {
                appState.exportSettings.gridSettings.rows = newValue
            }
        }

        Stepper(value: $state.exportSettings.gridSettings.rows, in: 1...10) {
            LabeledContent("Rows") {
                Text("\(rows)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }

        // Mini grid preview
        let cellSize: CGFloat = min(200.0 / CGFloat(max(columns, rows)), 32)
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(cellSize), spacing: 2), count: columns),
            spacing: 2
        ) {
            ForEach(0..<(rows * columns), id: \.self) { index in
                let row = index / columns + 1
                let col = index % columns + 1
                Text("\(row),\(col)")
                    .font(.system(size: max(7, cellSize * 0.28)))
                    .foregroundStyle(.secondary)
                    .frame(width: cellSize, height: cellSize)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.accentColor.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 0.5)
                            )
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 4)

        // Tile info line
        if let size = tileSize {
            Text("\(tileCount) tiles, each ~\(Int(size.width))×\(Int(size.height)) px")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Small tile warning
            if Int(size.width) < 50 || Int(size.height) < 50 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Tiles will be very small")
                        .foregroundStyle(.orange)
                }
                .font(.caption)
            }
        } else {
            Text("\(tileCount) tiles")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        // Naming suffix
        LabeledContent("Suffix") {
            TextField("_{row}_{col}", text: $state.exportSettings.gridSettings.namingSuffix)
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospaced())
                .frame(maxWidth: 120)
        }
        Text("Tokens: {row}, {col}")
            .font(.caption2)
            .foregroundStyle(.tertiary)

        // Output filename preview
        if let firstName = appState.activeImage?.url.deletingPathExtension().lastPathComponent {
            let ext = appState.exportSettings.format.fileExtension
            let suffix = appState.exportSettings.gridSettings.namingSuffix
            let preview = "\(firstName)\(suffix.replacingOccurrences(of: "{row}", with: "1").replacingOccurrences(of: "{col}", with: "1")).\(ext)"
            Text("e.g. \(preview)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
