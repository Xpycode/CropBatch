import SwiftUI

struct ImageGridView: View {
    @Environment(AppState.self) private var appState

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 250), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(appState.images) { item in
                    ImageThumbnailView(item: item)
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .toolbar {
            ToolbarItemGroup {
                Button {
                    appState.selectedImageIDs = Set(appState.images.map(\.id))
                } label: {
                    Label("Select All", systemImage: "checkmark.circle")
                }
                .disabled(appState.images.isEmpty)

                Button {
                    appState.selectedImageIDs.removeAll()
                } label: {
                    Label("Deselect All", systemImage: "circle")
                }
                .disabled(appState.selectedImageIDs.isEmpty)

                Divider()

                Button {
                    appState.showImportPanel()
                } label: {
                    Label("Add Images", systemImage: "plus")
                }

                Button(role: .destructive) {
                    if appState.selectedImageIDs.isEmpty {
                        appState.clearAll()
                    } else {
                        appState.removeImages(ids: appState.selectedImageIDs)
                    }
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .disabled(appState.images.isEmpty)
            }
        }
    }
}

struct ImageThumbnailView: View {
    let item: ImageItem
    @Environment(AppState.self) private var appState
    @State private var isHovering = false

    private var isSelected: Bool {
        appState.selectedImageIDs.contains(item.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: item.originalImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        if appState.cropSettings.hasAnyCrop {
                            CropPreviewOverlay(
                                imageSize: item.originalSize,
                                cropSettings: appState.cropSettings
                            )
                        }
                    }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .background(Circle().fill(.blue).padding(-2))
                        .padding(8)
                }
            }

            VStack(spacing: 2) {
                Text(item.filename)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("\(Int(item.originalSize.width)) × \(Int(item.originalSize.height))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(isHovering ? 0.1 : 0.05), radius: isHovering ? 8 : 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        }
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            if isSelected {
                appState.selectedImageIDs.remove(item.id)
            } else {
                appState.selectedImageIDs.insert(item.id)
            }
        }
    }
}

struct CropPreviewOverlay: View {
    let imageSize: CGSize
    let cropSettings: CropSettings

    var body: some View {
        GeometryReader { geometry in
            let scaleX = geometry.size.width / imageSize.width
            let scaleY = geometry.size.height / imageSize.height
            let scale = min(scaleX, scaleY)

            let displayedWidth = imageSize.width * scale
            let displayedHeight = imageSize.height * scale
            let offsetX = (geometry.size.width - displayedWidth) / 2
            let offsetY = (geometry.size.height - displayedHeight) / 2

            ZStack {
                // Top crop area
                if cropSettings.cropTop > 0 {
                    Rectangle()
                        .fill(Color.red.opacity(0.3))
                        .frame(
                            width: displayedWidth,
                            height: CGFloat(cropSettings.cropTop) * scale
                        )
                        .position(
                            x: offsetX + displayedWidth / 2,
                            y: offsetY + CGFloat(cropSettings.cropTop) * scale / 2
                        )
                }

                // Bottom crop area
                if cropSettings.cropBottom > 0 {
                    Rectangle()
                        .fill(Color.red.opacity(0.3))
                        .frame(
                            width: displayedWidth,
                            height: CGFloat(cropSettings.cropBottom) * scale
                        )
                        .position(
                            x: offsetX + displayedWidth / 2,
                            y: offsetY + displayedHeight - CGFloat(cropSettings.cropBottom) * scale / 2
                        )
                }

                // Left crop area
                if cropSettings.cropLeft > 0 {
                    Rectangle()
                        .fill(Color.red.opacity(0.3))
                        .frame(
                            width: CGFloat(cropSettings.cropLeft) * scale,
                            height: displayedHeight - CGFloat(cropSettings.cropTop + cropSettings.cropBottom) * scale
                        )
                        .position(
                            x: offsetX + CGFloat(cropSettings.cropLeft) * scale / 2,
                            y: offsetY + displayedHeight / 2
                        )
                }

                // Right crop area
                if cropSettings.cropRight > 0 {
                    Rectangle()
                        .fill(Color.red.opacity(0.3))
                        .frame(
                            width: CGFloat(cropSettings.cropRight) * scale,
                            height: displayedHeight - CGFloat(cropSettings.cropTop + cropSettings.cropBottom) * scale
                        )
                        .position(
                            x: offsetX + displayedWidth - CGFloat(cropSettings.cropRight) * scale / 2,
                            y: offsetY + displayedHeight / 2
                        )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    let state = AppState()
    return ImageGridView()
        .environment(state)
        .frame(width: 600, height: 400)
}
