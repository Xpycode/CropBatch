import Foundation

struct CropSettings: Equatable, Codable {
    var cropTop: Int = 0
    var cropBottom: Int = 0
    var cropLeft: Int = 0
    var cropRight: Int = 0

    var hasAnyCrop: Bool {
        cropTop > 0 || cropBottom > 0 || cropLeft > 0 || cropRight > 0
    }

    func croppedSize(from originalSize: CGSize) -> CGSize {
        let width = max(0, originalSize.width - CGFloat(cropLeft + cropRight))
        let height = max(0, originalSize.height - CGFloat(cropTop + cropBottom))
        return CGSize(width: width, height: height)
    }

    /// Set vertical (top/bottom) edges to same value
    mutating func setVerticalCrop(_ value: Int) {
        cropTop = value
        cropBottom = value
    }

    /// Set horizontal (left/right) edges to same value
    mutating func setHorizontalCrop(_ value: Int) {
        cropLeft = value
        cropRight = value
    }

    /// Set all edges to same value
    mutating func setAllEdges(_ value: Int) {
        cropTop = value
        cropBottom = value
        cropLeft = value
        cropRight = value
    }
}

/// Edge linking mode for synchronized cropping
enum EdgeLinkMode: String, CaseIterable, Identifiable {
    case none = "None"
    case vertical = "Top ↔ Bottom"
    case horizontal = "Left ↔ Right"
    case all = "All Edges"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .none: return "link.slash"
        case .vertical: return "arrow.up.and.down"
        case .horizontal: return "arrow.left.and.right"
        case .all: return "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left"
        }
    }
}

/// Common aspect ratios for guides
enum AspectRatioGuide: String, CaseIterable, Identifiable {
    case ratio16x9 = "16:9"
    case ratio4x3 = "4:3"
    case ratio1x1 = "1:1"
    case ratio9x16 = "9:16"
    case ratio3x2 = "3:2"
    case ratio21x9 = "21:9"

    var id: String { rawValue }

    /// The aspect ratio as width/height
    var ratio: CGFloat {
        switch self {
        case .ratio16x9: return 16.0 / 9.0
        case .ratio4x3: return 4.0 / 3.0
        case .ratio1x1: return 1.0
        case .ratio9x16: return 9.0 / 16.0
        case .ratio3x2: return 3.0 / 2.0
        case .ratio21x9: return 21.0 / 9.0
        }
    }

    var description: String {
        switch self {
        case .ratio16x9: return "Widescreen"
        case .ratio4x3: return "Classic"
        case .ratio1x1: return "Square"
        case .ratio9x16: return "Portrait"
        case .ratio3x2: return "Photo"
        case .ratio21x9: return "Ultrawide"
        }
    }

    var icon: String {
        switch self {
        case .ratio16x9: return "rectangle.ratio.16.to.9"
        case .ratio4x3: return "rectangle.ratio.4.to.3"
        case .ratio1x1: return "square"
        case .ratio9x16: return "rectangle.portrait"
        case .ratio3x2: return "rectangle.ratio.3.to.2"
        case .ratio21x9: return "rectangle"
        }
    }
}

enum CropEdge: String, CaseIterable, Identifiable {
    case top = "Top"
    case bottom = "Bottom"
    case left = "Left"
    case right = "Right"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .top: return "arrow.up.to.line"
        case .bottom: return "arrow.down.to.line"
        case .left: return "arrow.left.to.line"
        case .right: return "arrow.right.to.line"
        }
    }
}
