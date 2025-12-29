import SwiftUI

struct BatchReviewView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let images: [ImageItem]
    let outputDirectory: URL
    let onConfirm: ([ImageItem]) -> Void

    @State private var previews: [PreviewItem] = []
    @State private var isGenerating = true
    @State private var selectedIDs: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Preview grid
            if isGenerating {
                generatingView
            } else {
                previewGrid
            }

            Divider()

            // Footer with actions
            footer
        }
        .frame(minWidth: 700, minHeight: 500)
        .task {
            await generatePreviews()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Review Cropped Images")
                    .font(.headline)
                Text("\(selectedIDs.count) of \(previews.count) selected for export")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Select all / none buttons
            HStack(spacing: 8) {
                Button("Select All") {
                    selectedIDs = Set(previews.map { $0.id })
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

                Button("Select None") {
                    selectedIDs.removeAll()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding()
    }

    // MARK: - Generating View

    private var generatingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Generating previews...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Preview Grid

    private var previewGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200))], spacing: 16) {
                ForEach(previews) { item in
                    PreviewItemView(
                        item: item,
                        isSelected: selectedIDs.contains(item.id)
                    ) {
                        toggleSelection(item.id)
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            // Output info
            VStack(alignment: .leading, spacing: 2) {
                Text("Output: \(outputDirectory.lastPathComponent)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let firstPreview = previews.first {
                    Text("Size: \(Int(firstPreview.croppedSize.width)) × \(Int(firstPreview.croppedSize.height))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Cancel / Export buttons
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("Export \(selectedIDs.count) Images") {
                let selectedImages = images.filter { selectedIDs.contains($0.id) }
                onConfirm(selectedImages)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(selectedIDs.isEmpty)
        }
        .padding()
    }

    // MARK: - Actions

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func generatePreviews() async {
        var items: [PreviewItem] = []

        for image in images {
            do {
                // Apply full processing pipeline to match export output
                let processed = try await generatePreview(for: image)
                let croppedSize = appState.cropSettings.croppedSize(from: image.originalSize)

                items.append(PreviewItem(
                    id: image.id,
                    filename: image.filename,
                    originalImage: image.originalImage,
                    croppedImage: processed,
                    croppedSize: croppedSize
                ))
            } catch {
                // Skip images that fail to process
                continue
            }
        }

        await MainActor.run {
            previews = items
            selectedIDs = Set(items.map { $0.id })  // Select all by default
            isGenerating = false
        }
    }

    /// Generates a preview by applying the full processing pipeline
    /// Matches the export pipeline: Transform -> Blur -> Crop -> Resize
    private func generatePreview(for item: ImageItem) async throws -> NSImage {
        var result = item.originalImage

        // 1. Apply transforms (rotation, flip) - global transform applies to all
        if !appState.imageTransform.isIdentity {
            result = ImageCropService.applyTransform(result, transform: appState.imageTransform)
        }

        // 2. Apply blur regions
        if let blurData = appState.blurRegions[item.id], !blurData.regions.isEmpty {
            result = ImageCropService.applyBlurRegions(result, regions: blurData.regions)
        }

        // 3. Apply crop
        if appState.cropSettings.hasAnyCrop {
            result = try ImageCropService.crop(result, with: appState.cropSettings)
        }

        // 4. Apply resize if enabled
        if appState.exportSettings.resizeSettings.isEnabled,
           let targetSize = ImageCropService.calculateResizedSize(
               from: result.size,
               with: appState.exportSettings.resizeSettings
           ) {
            result = ImageCropService.resize(result, to: targetSize)
        }

        return result
    }
}

// MARK: - Preview Item Model

struct PreviewItem: Identifiable {
    let id: UUID
    let filename: String
    let originalImage: NSImage
    let croppedImage: NSImage
    let croppedSize: CGSize
}

// MARK: - Preview Item View

struct PreviewItemView: View {
    let item: PreviewItem
    let isSelected: Bool
    let onToggle: () -> Void

    @State private var showOriginal = false

    var body: some View {
        VStack(spacing: 6) {
            // Image preview with toggle
            ZStack(alignment: .topTrailing) {
                Image(nsImage: showOriginal ? item.originalImage : item.croppedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isSelected ? 3 : 1)
                    }
                    .opacity(isSelected ? 1 : 0.5)

                // Selection checkbox
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .background(Circle().fill(.white).padding(2))
                    .offset(x: 6, y: -6)
            }
            .onTapGesture {
                onToggle()
            }

            // Filename
            Text(item.filename)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 140)

            // Toggle original/cropped
            Button {
                showOriginal.toggle()
            } label: {
                Text(showOriginal ? "Showing Original" : "Showing Cropped")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.05) : Color.clear)
        )
    }
}

#Preview {
    BatchReviewView(
        images: [],
        outputDirectory: URL(fileURLWithPath: "/tmp")
    ) { _ in }
    .environment(AppState())
}
