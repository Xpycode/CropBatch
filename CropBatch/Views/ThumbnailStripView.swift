import SwiftUI
import UniformTypeIdentifiers

struct ThumbnailStripView: View {
    @Environment(AppState.self) private var appState
    @State private var draggedItem: ImageItem?

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack(spacing: 12) {
                            ForEach(appState.images) { item in
                                ThumbnailItemView(item: item, draggedItem: $draggedItem)
                                    .id(item.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: appState.activeImageID) { _, newID in
                        scrollToActive(proxy: proxy, activeID: newID)
                    }
                }
                .frame(height: 110)
                .background(Color(nsColor: .windowBackgroundColor))

                // Position counter and loop toggle
                if !appState.images.isEmpty {
                    endControls
                }
            }
        }
    }


    private var endControls: some View {
        let currentIndex = appState.images.firstIndex { $0.id == appState.activeImageID } ?? 0

        return VStack(spacing: 4) {
            // Loop toggle styled like a thumbnail
            Button {
                appState.loopNavigation.toggle()
            } label: {
                Image(systemName: appState.loopNavigation ? "repeat.circle.fill" : "repeat.circle")
                    .font(.title2)
                    .foregroundStyle(appState.loopNavigation ? Color.accentColor : Color.secondary)
                    .frame(width: 50, height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(appState.loopNavigation ? Color.accentColor.opacity(0.1) : Color.gray.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(appState.loopNavigation ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
            }
            .buttonStyle(.plain)
            .help(appState.loopNavigation ? "Loop navigation on" : "Loop navigation off")

            // Position counter
            Text("\(currentIndex + 1)/\(appState.images.count)")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
    }

    private func scrollToActive(proxy: ScrollViewProxy, activeID: UUID?) {
        guard let activeID = activeID,
              let activeIndex = appState.images.firstIndex(where: { $0.id == activeID }) else {
            return
        }

        // Target: scroll to show 3 items ahead (if possible)
        let targetIndex = min(activeIndex + 3, appState.images.count - 1)
        let targetID = appState.images[targetIndex].id

        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(targetID, anchor: .trailing)
        }
    }
}

struct ThumbnailItemView: View {
    @Environment(AppState.self) private var appState
    let item: ImageItem
    @Binding var draggedItem: ImageItem?

    @State private var isHovering = false
    @State private var isTargeted = false
    @State private var showQuickExport = false

    private var isActive: Bool {
        appState.activeImageID == item.id
    }

    private var isMismatched: Bool {
        appState.mismatchedImages.contains { $0.id == item.id }
    }

    private var hasBlurRegions: Bool {
        appState.blurRegionsForImage(item.id).count > 0
    }

    private var backgroundColor: Color {
        if isActive {
            return Color.accentColor.opacity(0.1)
        } else if isHovering {
            return Color.gray.opacity(0.1)
        }
        return Color.clear
    }

    var body: some View {
        thumbnailContent
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 8).fill(backgroundColor))
            .overlay(targetOverlay)
            .opacity(draggedItem?.id == item.id ? 0.5 : 1.0)
            .scaleEffect(isHovering && draggedItem == nil ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
            .onHover { isHovering = $0 }
            .onTapGesture { appState.setActiveImage(item.id) }
            .draggable(item.id.uuidString) { dragPreview }
            .dropDestination(for: String.self, action: handleDrop, isTargeted: { isTargeted = $0 })
            .contextMenu { contextMenuItems }
            .fileExporter(
                isPresented: $showQuickExport,
                document: makeExportDocument(),
                contentType: appState.exportSettings.format.utType,
                defaultFilename: appState.exportSettings.outputFilename(for: item.url)
            ) { _ in }
    }

    private var thumbnailContent: some View {
        VStack(spacing: 4) {
            thumbnailImage
            filenameLabel
        }
    }

    private var thumbnailImage: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: item.originalImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(cropOverlay)
                .overlay(selectionBorder)

            // Badges stack
            VStack(spacing: 2) {
                if isMismatched {
                    mismatchBadge
                }
                // Blur badge disabled for now
                // if hasBlurRegions {
                //     blurBadge
                // }
            }
            .offset(x: 4, y: -4)
        }
    }

    @ViewBuilder
    private var cropOverlay: some View {
        if appState.cropSettings.hasAnyCrop {
            ThumbnailCropOverlay(imageSize: item.originalSize, cropSettings: appState.cropSettings)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var selectionBorder: some View {
        RoundedRectangle(cornerRadius: 6)
            .strokeBorder(isActive ? Color.accentColor : Color.clear, lineWidth: 3)
    }

    private var mismatchBadge: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.yellow)
            .background(Circle().fill(Color.black.opacity(0.6)).padding(-2))
    }

    private var blurBadge: some View {
        Image(systemName: "eye.slash.fill")
            .font(.caption2)
            .foregroundStyle(.blue)
            .background(Circle().fill(Color.black.opacity(0.6)).padding(-2))
    }

    private var filenameLabel: some View {
        Text(item.filename)
            .font(.caption2)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(width: 100)
            .foregroundStyle(isActive ? .primary : .secondary)
    }

    @ViewBuilder
    private var targetOverlay: some View {
        if isTargeted {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor, lineWidth: 2, antialiased: true)
        }
    }

    private var dragPreview: some View {
        Image(nsImage: item.originalImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 80, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .onAppear { draggedItem = item }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Set as Active") { appState.setActiveImage(item.id) }
        Divider()
        Button("Copy Cropped to Clipboard") { copyToClipboard() }
            .disabled(!appState.cropSettings.hasAnyCrop)
        Button("Quick Export...") { showQuickExport = true }
            .disabled(!appState.cropSettings.hasAnyCrop)
        Divider()
        Button("Remove", role: .destructive) { appState.removeImages(ids: [item.id]) }
    }

    private func handleDrop(_ items: [String], _ location: CGPoint) -> Bool {
        guard let droppedID = items.first,
              let sourceID = UUID(uuidString: droppedID),
              let targetIndex = appState.images.firstIndex(where: { $0.id == item.id }) else {
            return false
        }
        appState.reorderImage(id: sourceID, toIndex: targetIndex)
        draggedItem = nil
        return true
    }

    private func makeExportDocument() -> CroppedImageDocument {
        CroppedImageDocument(
            image: item.originalImage,
            cropSettings: appState.cropSettings,
            exportSettings: appState.exportSettings
        )
    }

    private func copyToClipboard() {
        do {
            let cropped = try ImageCropService.crop(item.originalImage, with: appState.cropSettings)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([cropped])
        } catch {
            print("Copy failed: \(error)")
        }
    }
}

// MARK: - Document for Quick Export

struct CroppedImageDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.png, .jpeg]

    let image: NSImage
    let cropSettings: CropSettings
    let exportSettings: ExportSettings

    init(image: NSImage, cropSettings: CropSettings, exportSettings: ExportSettings) {
        self.image = image
        self.cropSettings = cropSettings
        self.exportSettings = exportSettings
    }

    init(configuration: ReadConfiguration) throws {
        fatalError("Reading not supported")
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let cropped = try ImageCropService.crop(image, with: cropSettings)
        guard let data = ImageCropService.encode(cropped, format: exportSettings.format, quality: exportSettings.quality) else {
            throw NSError(domain: "CropBatch", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode image"])
        }
        return FileWrapper(regularFileWithContents: data)
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
