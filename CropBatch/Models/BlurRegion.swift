import Foundation

/// A rectangular region to be blurred/redacted in an image
struct BlurRegion: Identifiable, Equatable {
    let id = UUID()
    var rect: CGRect  // In image coordinates (pixels)
    var style: BlurStyle = .blur

    enum BlurStyle: String, CaseIterable, Identifiable {
        case blur = "Blur"
        case pixelate = "Pixelate"
        case solidBlack = "Black"
        case solidWhite = "White"

        var id: String { rawValue }
    }
}

/// Per-image blur regions storage
struct ImageBlurData: Equatable {
    var regions: [BlurRegion] = []

    var hasRegions: Bool {
        !regions.isEmpty
    }
}
