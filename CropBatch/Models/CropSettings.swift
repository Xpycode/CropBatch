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
