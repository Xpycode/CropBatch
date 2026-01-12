import Foundation

/// Rotation angle in 90-degree increments
enum RotationAngle: Int, CaseIterable, Identifiable, Codable {
    case none = 0
    case cw90 = 90
    case cw180 = 180
    case cw270 = 270

    var id: Int { rawValue }

    /// Whether this rotation swaps width and height
    var swapsWidthAndHeight: Bool {
        self == .cw90 || self == .cw270
    }

    /// Rotate 90 degrees clockwise
    mutating func rotateCW() {
        self = RotationAngle(rawValue: (rawValue + 90) % 360) ?? .none
    }

    /// Rotate 90 degrees counter-clockwise
    mutating func rotateCCW() {
        self = RotationAngle(rawValue: (rawValue + 270) % 360) ?? .none
    }

    /// Display name for UI
    var displayName: String {
        switch self {
        case .none: return "0°"
        case .cw90: return "90°"
        case .cw180: return "180°"
        case .cw270: return "270°"
        }
    }
}

/// Transform state for an image (rotation + flip)
struct ImageTransform: Equatable, Codable {
    var rotation: RotationAngle = .none
    var flipHorizontal: Bool = false
    var flipVertical: Bool = false

    static let identity = ImageTransform()

    var isIdentity: Bool { self == .identity }

    /// Whether this transform swaps width and height
    var swapsWidthAndHeight: Bool {
        rotation.swapsWidthAndHeight
    }

    /// Apply this transform's dimension change to a size
    func transformedSize(_ size: CGSize) -> CGSize {
        if swapsWidthAndHeight {
            return CGSize(width: size.height, height: size.width)
        }
        return size
    }
}
