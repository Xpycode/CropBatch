import Foundation
import AppKit

// MARK: - Watermark Position

/// Predefined anchor positions for watermark placement
enum WatermarkPosition: String, CaseIterable, Identifiable, Codable {
    case topLeft = "Top Left"
    case topCenter = "Top Center"
    case topRight = "Top Right"
    case centerLeft = "Center Left"
    case center = "Center"
    case centerRight = "Center Right"
    case bottomLeft = "Bottom Left"
    case bottomCenter = "Bottom Center"
    case bottomRight = "Bottom Right"

    var id: String { rawValue }

    /// SF Symbol for position indicator
    var symbolName: String {
        switch self {
        case .topLeft: return "arrow.up.left"
        case .topCenter: return "arrow.up"
        case .topRight: return "arrow.up.right"
        case .centerLeft: return "arrow.left"
        case .center: return "circle"
        case .centerRight: return "arrow.right"
        case .bottomLeft: return "arrow.down.left"
        case .bottomCenter: return "arrow.down"
        case .bottomRight: return "arrow.down.right"
        }
    }

    /// Returns normalized anchor point (0-1) for this position
    var normalizedAnchor: CGPoint {
        switch self {
        case .topLeft:      return CGPoint(x: 0.0, y: 0.0)
        case .topCenter:    return CGPoint(x: 0.5, y: 0.0)
        case .topRight:     return CGPoint(x: 1.0, y: 0.0)
        case .centerLeft:   return CGPoint(x: 0.0, y: 0.5)
        case .center:       return CGPoint(x: 0.5, y: 0.5)
        case .centerRight:  return CGPoint(x: 1.0, y: 0.5)
        case .bottomLeft:   return CGPoint(x: 0.0, y: 1.0)
        case .bottomCenter: return CGPoint(x: 0.5, y: 1.0)
        case .bottomRight:  return CGPoint(x: 1.0, y: 1.0)
        }
    }
}

// MARK: - Watermark Sizing Mode

/// How the watermark size is determined
enum WatermarkSizeMode: String, CaseIterable, Identifiable, Codable {
    case original = "Original Size"
    case percentage = "% of Image"
    case fixedWidth = "Fixed Width"
    case fixedHeight = "Fixed Height"

    var id: String { rawValue }
}

// MARK: - Watermark Settings

/// Configuration for image watermark overlay
struct WatermarkSettings: Equatable {
    /// Whether watermarking is enabled
    var isEnabled: Bool = false

    /// URL to the watermark PNG image (for display purposes)
    var imageURL: URL?

    /// Stored image data - survives state changes unlike security-scoped URLs
    var imageData: Data?

    /// Cached NSImage (reconstructed from imageData on demand)
    var cachedImage: NSImage?

    /// Position anchor for watermark placement
    var position: WatermarkPosition = .bottomRight

    /// Opacity (0.0 = invisible, 1.0 = fully opaque)
    var opacity: Double = 0.5

    /// Sizing mode
    var sizeMode: WatermarkSizeMode = .percentage

    /// Size value - interpretation depends on sizeMode:
    /// - .original: ignored
    /// - .percentage: percentage of image width (e.g., 20 = 20%)
    /// - .fixedWidth: width in pixels
    /// - .fixedHeight: height in pixels
    var sizeValue: Double = 20

    /// Margin from edges in pixels
    var margin: Double = 20

    /// Additional X offset from anchor position (in pixels, can be negative)
    var offsetX: Double = 0

    /// Additional Y offset from anchor position (in pixels, can be negative)
    var offsetY: Double = 0

    /// Whether settings are valid for processing
    var isValid: Bool {
        isEnabled && imageURL != nil && loadedImage != nil
    }

    /// Loads and returns the watermark image (uses cache, then reconstructs from data)
    var loadedImage: NSImage? {
        if let cached = cachedImage {
            return cached
        }
        // Reconstruct from stored image data (security-scoped URL not accessible)
        if let data = imageData {
            return NSImage(data: data)
        }
        return nil
    }

    /// Calculates the watermark size for a given target image size
    func watermarkSize(for imageSize: CGSize) -> CGSize? {
        guard let watermark = loadedImage else { return nil }
        let originalSize = watermark.size
        guard originalSize.width > 0 && originalSize.height > 0 else { return nil }

        let aspectRatio = originalSize.width / originalSize.height

        switch sizeMode {
        case .original:
            return originalSize

        case .percentage:
            let targetWidth = imageSize.width * (sizeValue / 100.0)
            return CGSize(width: targetWidth, height: targetWidth / aspectRatio)

        case .fixedWidth:
            return CGSize(width: sizeValue, height: sizeValue / aspectRatio)

        case .fixedHeight:
            return CGSize(width: sizeValue * aspectRatio, height: sizeValue)
        }
    }

    /// Calculates the watermark rect for a given target image size
    /// Uses CGImage coordinates (origin at bottom-left)
    func watermarkRect(for imageSize: CGSize) -> CGRect? {
        guard let wmSize = watermarkSize(for: imageSize) else { return nil }

        let anchor = position.normalizedAnchor

        // Calculate position based on anchor
        // Note: In CGImage coords, Y=0 is bottom, so we flip the Y anchor
        let flippedAnchorY = 1.0 - anchor.y

        // Calculate available area (image size minus margins)
        let availableWidth = imageSize.width - (2 * margin)
        let availableHeight = imageSize.height - (2 * margin)

        // Position within available area, plus user offsets
        // offsetX: positive moves right
        // offsetY: positive moves down (but in CGImage coords, that means subtracting)
        let x = margin + (availableWidth - wmSize.width) * anchor.x + offsetX
        let y = margin + (availableHeight - wmSize.height) * flippedAnchorY - offsetY

        return CGRect(x: x, y: y, width: wmSize.width, height: wmSize.height)
    }

    // MARK: - Equatable

    static func == (lhs: WatermarkSettings, rhs: WatermarkSettings) -> Bool {
        lhs.isEnabled == rhs.isEnabled &&
        lhs.imageURL == rhs.imageURL &&
        lhs.imageData == rhs.imageData &&
        lhs.position == rhs.position &&
        lhs.opacity == rhs.opacity &&
        lhs.sizeMode == rhs.sizeMode &&
        lhs.sizeValue == rhs.sizeValue &&
        lhs.margin == rhs.margin &&
        lhs.offsetX == rhs.offsetX &&
        lhs.offsetY == rhs.offsetY
    }
}

// MARK: - Codable Support

extension WatermarkSettings: Codable {
    enum CodingKeys: String, CodingKey {
        case isEnabled, imageURL, imageData, position, opacity, sizeMode, sizeValue, margin, offsetX, offsetY
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        imageURL = try container.decodeIfPresent(URL.self, forKey: .imageURL)
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        position = try container.decode(WatermarkPosition.self, forKey: .position)
        opacity = try container.decode(Double.self, forKey: .opacity)
        sizeMode = try container.decode(WatermarkSizeMode.self, forKey: .sizeMode)
        sizeValue = try container.decode(Double.self, forKey: .sizeValue)
        margin = try container.decode(Double.self, forKey: .margin)
        offsetX = try container.decodeIfPresent(Double.self, forKey: .offsetX) ?? 0
        offsetY = try container.decodeIfPresent(Double.self, forKey: .offsetY) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encodeIfPresent(imageURL, forKey: .imageURL)
        try container.encodeIfPresent(imageData, forKey: .imageData)
        try container.encode(position, forKey: .position)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(sizeMode, forKey: .sizeMode)
        try container.encode(sizeValue, forKey: .sizeValue)
        try container.encode(margin, forKey: .margin)
        try container.encode(offsetX, forKey: .offsetX)
        try container.encode(offsetY, forKey: .offsetY)
    }
}
