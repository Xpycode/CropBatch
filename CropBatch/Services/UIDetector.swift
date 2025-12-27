import AppKit
import CoreGraphics

struct UIDetectionResult {
    var suggestedTop: Int = 0
    var suggestedBottom: Int = 0
    var suggestedLeft: Int = 0
    var suggestedRight: Int = 0

    var topDescription: String?
    var bottomDescription: String?

    var hasDetection: Bool {
        suggestedTop > 0 || suggestedBottom > 0 || suggestedLeft > 0 || suggestedRight > 0
    }

    var asCropSettings: CropSettings {
        CropSettings(
            cropTop: suggestedTop,
            cropBottom: suggestedBottom,
            cropLeft: suggestedLeft,
            cropRight: suggestedRight
        )
    }
}

struct UIDetector {

    /// Known UI element heights for detection heuristics
    private static let knownHeights: [(range: ClosedRange<Int>, description: String)] = [
        // macOS
        (22...25, "macOS menu bar"),
        (28...30, "macOS window title bar"),
        (48...52, "macOS menu bar + title bar"),
        (50...52, "macOS menu bar (Retina)"),

        // iOS Status Bars
        (20...20, "iOS status bar (pre-iPhone X)"),
        (44...47, "iOS status bar (notch)"),
        (54...59, "iOS Dynamic Island status bar"),

        // iOS Home Indicator
        (21...21, "iOS home indicator (iPhone X+)"),
        (34...34, "iOS home indicator area"),

        // Browsers
        (52...56, "Browser tab bar"),
        (85...92, "Browser full chrome"),

        // Windows (various)
        (80...85, "macOS Dock area"),
    ]

    /// Analyze an image and detect UI elements that could be cropped
    static func detect(in image: NSImage) -> UIDetectionResult {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return UIDetectionResult()
        }

        var result = UIDetectionResult()

        // Detect top bar
        if let topHeight = detectSolidBar(in: cgImage, from: .top) {
            result.suggestedTop = topHeight
            result.topDescription = describeHeight(topHeight)
        }

        // Detect bottom bar
        if let bottomHeight = detectSolidBar(in: cgImage, from: .bottom) {
            result.suggestedBottom = bottomHeight
            result.bottomDescription = describeHeight(bottomHeight)
        }

        return result
    }

    /// Detect a solid-colored bar from the specified edge
    private static func detectSolidBar(in image: CGImage, from edge: Edge) -> Int? {
        let width = image.width
        let height = image.height

        guard let context = createContext(for: image),
              let data = context.data else {
            return nil
        }

        let bytesPerRow = context.bytesPerRow
        let bytesPerPixel = 4

        // Sample multiple x positions across the width
        let samplePositions = [
            width / 4,
            width / 2,
            3 * width / 4
        ]

        // Get the edge color from first row/column
        let edgeY = edge == .top ? 0 : height - 1
        guard let edgeColor = getAverageColor(data: data, y: edgeY, width: width, bytesPerRow: bytesPerRow, bytesPerPixel: bytesPerPixel, samplePositions: samplePositions) else {
            return nil
        }

        // Scan inward to find where color changes
        let maxScan = min(height / 3, 150)  // Don't scan more than 1/3 of image or 150px
        var barHeight = 0

        for offset in 1..<maxScan {
            let y = edge == .top ? offset : height - 1 - offset

            guard let rowColor = getAverageColor(data: data, y: y, width: width, bytesPerRow: bytesPerRow, bytesPerPixel: bytesPerPixel, samplePositions: samplePositions) else {
                break
            }

            // Check if color is similar enough to edge color
            if colorDistance(edgeColor, rowColor) < 15 {
                barHeight = offset + 1
            } else {
                break
            }
        }

        // Only return if we found a meaningful bar (at least 15px)
        return barHeight >= 15 ? barHeight : nil
    }

    /// Create a bitmap context for reading pixel data
    private static func createContext(for image: CGImage) -> CGContext? {
        let width = image.width
        let height = image.height

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ).map { context in
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return context
        }
    }

    /// Get average color from sample positions in a row
    private static func getAverageColor(
        data: UnsafeMutableRawPointer,
        y: Int,
        width: Int,
        bytesPerRow: Int,
        bytesPerPixel: Int,
        samplePositions: [Int]
    ) -> (r: Int, g: Int, b: Int)? {
        var totalR = 0, totalG = 0, totalB = 0
        var count = 0

        for x in samplePositions {
            guard x >= 0 && x < width else { continue }

            let offset = y * bytesPerRow + x * bytesPerPixel
            let ptr = data.advanced(by: offset).assumingMemoryBound(to: UInt8.self)

            totalR += Int(ptr[0])
            totalG += Int(ptr[1])
            totalB += Int(ptr[2])
            count += 1
        }

        guard count > 0 else { return nil }
        return (totalR / count, totalG / count, totalB / count)
    }

    /// Calculate color distance (simple RGB distance)
    private static func colorDistance(
        _ c1: (r: Int, g: Int, b: Int),
        _ c2: (r: Int, g: Int, b: Int)
    ) -> Int {
        let dr = c1.r - c2.r
        let dg = c1.g - c2.g
        let db = c1.b - c2.b
        return abs(dr) + abs(dg) + abs(db)
    }

    /// Try to match height to known UI element
    private static func describeHeight(_ height: Int) -> String? {
        for (range, description) in knownHeights {
            if range.contains(height) {
                return description
            }
        }
        return nil
    }

    private enum Edge {
        case top, bottom
    }
}

// MARK: - Batch Detection

extension UIDetector {

    /// Analyze multiple images and find common UI patterns
    static func detectCommon(in images: [ImageItem]) -> UIDetectionResult {
        guard !images.isEmpty else { return UIDetectionResult() }

        // Detect for each image
        let results = images.map { detect(in: $0.originalImage) }

        // Find most common top crop value
        let topCounts = Dictionary(grouping: results.filter { $0.suggestedTop > 0 }, by: { $0.suggestedTop })
        let mostCommonTop = topCounts.max(by: { $0.value.count < $1.value.count })

        // Find most common bottom crop value
        let bottomCounts = Dictionary(grouping: results.filter { $0.suggestedBottom > 0 }, by: { $0.suggestedBottom })
        let mostCommonBottom = bottomCounts.max(by: { $0.value.count < $1.value.count })

        var result = UIDetectionResult()

        // Only suggest if majority agree
        if let top = mostCommonTop, top.value.count > images.count / 2 {
            result.suggestedTop = top.key
            result.topDescription = top.value.first?.topDescription
        }

        if let bottom = mostCommonBottom, bottom.value.count > images.count / 2 {
            result.suggestedBottom = bottom.key
            result.bottomDescription = bottom.value.first?.bottomDescription
        }

        return result
    }
}
