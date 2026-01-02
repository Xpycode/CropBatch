import Foundation
import AppKit

// MARK: - Watermark Mode

/// Whether watermark uses an image or text
enum WatermarkMode: String, CaseIterable, Identifiable, Codable {
    case image = "Image"
    case text = "Text"

    var id: String { rawValue }
}

// MARK: - Text Watermark Dynamic Variables

/// Variables that can be used in text watermarks
enum TextWatermarkVariable: String, CaseIterable {
    case filename = "{filename}"
    case index = "{index}"
    case count = "{count}"
    case date = "{date}"
    case datetime = "{datetime}"
    case year = "{year}"
    case month = "{month}"
    case day = "{day}"

    var description: String {
        switch self {
        case .filename: return "Original filename"
        case .index: return "Image number (1, 2, 3...)"
        case .count: return "Total image count"
        case .date: return "Current date"
        case .datetime: return "Date and time"
        case .year: return "Year (4 digits)"
        case .month: return "Month (01-12)"
        case .day: return "Day (01-31)"
        }
    }

    /// Substitutes all variables in a template string
    static func substitute(
        in template: String,
        filename: String = "",
        index: Int = 1,
        count: Int = 1
    ) -> String {
        let now = Date()
        let dateFormatter = DateFormatter()

        var result = template

        // Filename (without extension)
        result = result.replacingOccurrences(of: "{filename}", with: filename)

        // Index and count
        result = result.replacingOccurrences(of: "{index}", with: "\(index)")
        result = result.replacingOccurrences(of: "{count}", with: "\(count)")

        // Date formats
        dateFormatter.dateFormat = "yyyy-MM-dd"
        result = result.replacingOccurrences(of: "{date}", with: dateFormatter.string(from: now))

        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        result = result.replacingOccurrences(of: "{datetime}", with: dateFormatter.string(from: now))

        dateFormatter.dateFormat = "yyyy"
        result = result.replacingOccurrences(of: "{year}", with: dateFormatter.string(from: now))

        dateFormatter.dateFormat = "MM"
        result = result.replacingOccurrences(of: "{month}", with: dateFormatter.string(from: now))

        dateFormatter.dateFormat = "dd"
        result = result.replacingOccurrences(of: "{day}", with: dateFormatter.string(from: now))

        return result
    }
}

// MARK: - Text Shadow Settings

struct TextShadowSettings: Equatable, Codable {
    var isEnabled: Bool = false
    var color: CodableColor = CodableColor(.black.withAlphaComponent(0.5))
    var blur: Double = 3
    var offsetX: Double = 2
    var offsetY: Double = 2
}

// MARK: - Text Outline Settings

struct TextOutlineSettings: Equatable, Codable {
    var isEnabled: Bool = false
    var color: CodableColor = CodableColor(.black)
    var width: Double = 1
}

// MARK: - Codable Color Wrapper

/// Wrapper for NSColor that supports Codable
struct CodableColor: Equatable, Codable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(_ color: NSColor) {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        self.red = rgb.redComponent
        self.green = rgb.greenComponent
        self.blue = rgb.blueComponent
        self.alpha = rgb.alphaComponent
    }

    init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    var nsColor: NSColor {
        NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    static var white: CodableColor { CodableColor(.white) }
    static var black: CodableColor { CodableColor(.black) }
}

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

/// Configuration for image or text watermark overlay
struct WatermarkSettings: Equatable {
    /// Whether watermarking is enabled
    var isEnabled: Bool = false

    /// Watermark mode (image or text)
    var mode: WatermarkMode = .image

    // MARK: - Image Mode Properties

    /// URL to the watermark PNG image (for display purposes)
    var imageURL: URL?

    /// Stored image data - survives state changes unlike security-scoped URLs
    var imageData: Data?

    /// Cached NSImage (reconstructed from imageData on demand)
    var cachedImage: NSImage?

    // MARK: - Text Mode Properties

    /// Text content (supports dynamic variables like {filename}, {date})
    var text: String = "© {year}"

    /// Font family name
    var fontFamily: String = "Helvetica Neue"

    /// Font size in points (for text mode)
    var fontSize: Double = 48

    /// Bold text
    var isBold: Bool = false

    /// Italic text
    var isItalic: Bool = false

    /// Text color
    var textColor: CodableColor = .white

    /// Shadow settings
    var shadow: TextShadowSettings = TextShadowSettings()

    /// Outline/stroke settings
    var outline: TextOutlineSettings = TextOutlineSettings()

    // MARK: - Shared Properties

    /// Position anchor for watermark placement
    var position: WatermarkPosition = .bottomRight

    /// Opacity (0.0 = invisible, 1.0 = fully opaque)
    var opacity: Double = 0.5

    /// Sizing mode (for image watermarks)
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
        guard isEnabled else { return false }
        switch mode {
        case .image:
            return imageURL != nil && loadedImage != nil
        case .text:
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Whether image mode is valid
    var isImageValid: Bool {
        imageURL != nil && loadedImage != nil
    }

    /// Whether text mode is valid
    var isTextValid: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        var x = margin + (availableWidth - wmSize.width) * anchor.x + offsetX
        var y = margin + (availableHeight - wmSize.height) * flippedAnchorY - offsetY

        // Clamp position to keep watermark fully within image bounds
        x = max(0, min(imageSize.width - wmSize.width, x))
        y = max(0, min(imageSize.height - wmSize.height, y))

        return CGRect(x: x, y: y, width: wmSize.width, height: wmSize.height)
    }

    // MARK: - Text Helpers

    /// Returns the NSFont for current text settings
    var textFont: NSFont {
        var traits: NSFontTraitMask = []
        if isBold { traits.insert(.boldFontMask) }
        if isItalic { traits.insert(.italicFontMask) }

        let baseFont = NSFont(name: fontFamily, size: fontSize)
            ?? NSFont.systemFont(ofSize: fontSize)

        if traits.isEmpty {
            return baseFont
        }

        return NSFontManager.shared.font(
            withFamily: baseFont.familyName ?? fontFamily,
            traits: traits,
            weight: 5,
            size: fontSize
        ) ?? baseFont
    }

    /// Returns attributed string attributes for rendering
    func textAttributes(scale: CGFloat = 1.0) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [:]

        // Font (scaled)
        let scaledFont = NSFont(descriptor: textFont.fontDescriptor, size: fontSize * scale)
            ?? textFont
        attributes[.font] = scaledFont

        // Color with opacity
        attributes[.foregroundColor] = textColor.nsColor.withAlphaComponent(opacity)

        // Shadow
        if shadow.isEnabled {
            let nsShadow = NSShadow()
            nsShadow.shadowColor = shadow.color.nsColor
            nsShadow.shadowBlurRadius = shadow.blur * scale
            nsShadow.shadowOffset = NSSize(
                width: shadow.offsetX * scale,
                height: -shadow.offsetY * scale  // Flip Y for AppKit
            )
            attributes[.shadow] = nsShadow
        }

        // Outline (stroke)
        if outline.isEnabled {
            attributes[.strokeColor] = outline.color.nsColor
            attributes[.strokeWidth] = -outline.width * scale  // Negative for fill + stroke
        }

        return attributes
    }

    /// Calculates text size for given image dimensions
    func textSize(for imageSize: CGSize, text: String) -> CGSize {
        let attrs = textAttributes(scale: 1.0)
        let attrString = NSAttributedString(string: text, attributes: attrs)
        return attrString.size()
    }

    /// Calculates the text watermark rect for a given target image size
    func textWatermarkRect(for imageSize: CGSize, text: String) -> CGRect {
        let textSize = textSize(for: imageSize, text: text)

        let anchor = position.normalizedAnchor

        // In CGImage coords, Y=0 is bottom, so we flip the Y anchor
        let flippedAnchorY = 1.0 - anchor.y

        // Calculate available area (image size minus margins)
        let availableWidth = imageSize.width - (2 * margin)
        let availableHeight = imageSize.height - (2 * margin)

        // Position within available area, plus user offsets
        var x = margin + (availableWidth - textSize.width) * anchor.x + offsetX
        var y = margin + (availableHeight - textSize.height) * flippedAnchorY - offsetY

        // Clamp position to keep watermark fully within image bounds
        x = max(0, min(imageSize.width - textSize.width, x))
        y = max(0, min(imageSize.height - textSize.height, y))

        return CGRect(x: x, y: y, width: textSize.width, height: textSize.height)
    }

    // MARK: - Equatable

    static func == (lhs: WatermarkSettings, rhs: WatermarkSettings) -> Bool {
        lhs.isEnabled == rhs.isEnabled &&
        lhs.mode == rhs.mode &&
        // Image properties
        lhs.imageURL == rhs.imageURL &&
        lhs.imageData == rhs.imageData &&
        // Text properties
        lhs.text == rhs.text &&
        lhs.fontFamily == rhs.fontFamily &&
        lhs.fontSize == rhs.fontSize &&
        lhs.isBold == rhs.isBold &&
        lhs.isItalic == rhs.isItalic &&
        lhs.textColor == rhs.textColor &&
        lhs.shadow == rhs.shadow &&
        lhs.outline == rhs.outline &&
        // Shared properties
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
        case isEnabled, mode
        // Image
        case imageURL, imageData
        // Text
        case text, fontFamily, fontSize, isBold, isItalic, textColor, shadow, outline
        // Shared
        case position, opacity, sizeMode, sizeValue, margin, offsetX, offsetY
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        mode = try container.decodeIfPresent(WatermarkMode.self, forKey: .mode) ?? .image

        // Image properties
        imageURL = try container.decodeIfPresent(URL.self, forKey: .imageURL)
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)

        // Text properties
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? "© {year}"
        fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily) ?? "Helvetica Neue"
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 48
        isBold = try container.decodeIfPresent(Bool.self, forKey: .isBold) ?? false
        isItalic = try container.decodeIfPresent(Bool.self, forKey: .isItalic) ?? false
        textColor = try container.decodeIfPresent(CodableColor.self, forKey: .textColor) ?? .white
        shadow = try container.decodeIfPresent(TextShadowSettings.self, forKey: .shadow) ?? TextShadowSettings()
        outline = try container.decodeIfPresent(TextOutlineSettings.self, forKey: .outline) ?? TextOutlineSettings()

        // Shared properties
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
        try container.encode(mode, forKey: .mode)

        // Image properties
        try container.encodeIfPresent(imageURL, forKey: .imageURL)
        try container.encodeIfPresent(imageData, forKey: .imageData)

        // Text properties
        try container.encode(text, forKey: .text)
        try container.encode(fontFamily, forKey: .fontFamily)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(isBold, forKey: .isBold)
        try container.encode(isItalic, forKey: .isItalic)
        try container.encode(textColor, forKey: .textColor)
        try container.encode(shadow, forKey: .shadow)
        try container.encode(outline, forKey: .outline)

        // Shared properties
        try container.encode(position, forKey: .position)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(sizeMode, forKey: .sizeMode)
        try container.encode(sizeValue, forKey: .sizeValue)
        try container.encode(margin, forKey: .margin)
        try container.encode(offsetX, forKey: .offsetX)
        try container.encode(offsetY, forKey: .offsetY)
    }
}
