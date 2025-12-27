import SwiftUI

struct ThumbnailStripView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 12) {
                    ForEach(appState.images) { item in
                        ThumbnailItemView(item: item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .frame(height: 110)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

struct ThumbnailItemView: View {
    @Environment(AppState.self) private var appState
    let item: ImageItem

    @State private var isHovering = false

    private var isActive: Bool {
        appState.activeImageID == item.id
    }

    private var isMismatched: Bool {
        appState.mismatchedImages.contains { $0.id == item.id }
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                // Thumbnail with crop preview
                Image(nsImage: item.originalImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        if appState.cropSettings.hasAnyCrop {
                            ThumbnailCropOverlay(
                                imageSize: item.originalSize,
                                cropSettings: appState.cropSettings
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                isActive ? Color.accentColor : Color.clear,
                                lineWidth: 3
                            )
                    }

                // Mismatch warning badge
                if isMismatched {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.6))
                                .padding(-2)
                        )
                        .offset(x: 4, y: -4)
                }
            }

            // Filename
            Text(item.filename)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 100)
                .foregroundStyle(isActive ? .primary : .secondary)
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Color.accentColor.opacity(0.1) : (isHovering ? Color.gray.opacity(0.1) : Color.clear))
        }
        .scaleEffect(isHovering ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            appState.setActiveImage(item.id)
        }
    }
}

struct ThumbnailCropOverlay: View {
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
                // Calculate the middle section (between top and bottom crops)
                let middleTop = offsetY + CGFloat(cropSettings.cropTop) * scale
                let middleHeight = displayedHeight - CGFloat(cropSettings.cropTop + cropSettings.cropBottom) * scale
                let middleCenterY = middleTop + middleHeight / 2

                // Top
                if cropSettings.cropTop > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: displayedWidth, height: CGFloat(cropSettings.cropTop) * scale)
                        .position(
                            x: offsetX + displayedWidth / 2,
                            y: offsetY + CGFloat(cropSettings.cropTop) * scale / 2
                        )
                }

                // Bottom
                if cropSettings.cropBottom > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: displayedWidth, height: CGFloat(cropSettings.cropBottom) * scale)
                        .position(
                            x: offsetX + displayedWidth / 2,
                            y: offsetY + displayedHeight - CGFloat(cropSettings.cropBottom) * scale / 2
                        )
                }

                // Left (middle section only)
                if cropSettings.cropLeft > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.5))
                        .frame(
                            width: CGFloat(cropSettings.cropLeft) * scale,
                            height: middleHeight
                        )
                        .position(
                            x: offsetX + CGFloat(cropSettings.cropLeft) * scale / 2,
                            y: middleCenterY
                        )
                }

                // Right (middle section only)
                if cropSettings.cropRight > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.5))
                        .frame(
                            width: CGFloat(cropSettings.cropRight) * scale,
                            height: middleHeight
                        )
                        .position(
                            x: offsetX + displayedWidth - CGFloat(cropSettings.cropRight) * scale / 2,
                            y: middleCenterY
                        )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    ThumbnailStripView()
        .environment(AppState())
        .frame(width: 600)
}
