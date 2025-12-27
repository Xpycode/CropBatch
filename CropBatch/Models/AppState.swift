import SwiftUI
import UniformTypeIdentifiers

@Observable
final class AppState {
    var images: [ImageItem] = []
    var cropSettings = CropSettings()
    var showFileImporter = false
    var isProcessing = false
    var processingProgress: Double = 0
    var selectedImageIDs: Set<UUID> = []

    var selectedImages: [ImageItem] {
        images.filter { selectedImageIDs.contains($0.id) }
    }

    func addImages(from urls: [URL]) {
        let newImages = urls.compactMap { url -> ImageItem? in
            guard let image = NSImage(contentsOf: url) else { return nil }
            return ImageItem(url: url, originalImage: image)
        }
        images.append(contentsOf: newImages)
    }

    func removeImages(ids: Set<UUID>) {
        images.removeAll { ids.contains($0.id) }
        selectedImageIDs.subtract(ids)
    }

    func clearAll() {
        images.removeAll()
        selectedImageIDs.removeAll()
    }
}

struct ImageItem: Identifiable {
    let id = UUID()
    let url: URL
    let originalImage: NSImage
    var isProcessed = false

    var filename: String {
        url.lastPathComponent
    }

    var originalSize: CGSize {
        originalImage.size
    }
}
