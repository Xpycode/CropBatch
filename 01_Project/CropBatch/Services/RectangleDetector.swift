import Vision
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Snap Points

/// Represents detected edges that can be used as snap targets
struct SnapPoints: Equatable {
    /// Horizontal edges (Y positions in pixels from top)
    var horizontalEdges: [Int] = []

    /// Vertical edges (X positions in pixels from left)
    var verticalEdges: [Int] = []

    /// Whether any snap points were detected
    var hasDetections: Bool {
        !horizontalEdges.isEmpty || !verticalEdges.isEmpty
    }

    /// Find the nearest horizontal edge within threshold
    func nearestHorizontalEdge(to value: Int, threshold: Int = 15) -> Int? {
        horizontalEdges
            .min(by: { abs($0 - value) < abs($1 - value) })
            .flatMap { abs($0 - value) <= threshold ? $0 : nil }
    }

    /// Find the nearest vertical edge within threshold
    func nearestVerticalEdge(to value: Int, threshold: Int = 15) -> Int? {
        verticalEdges
            .min(by: { abs($0 - value) < abs($1 - value) })
            .flatMap { abs($0 - value) <= threshold ? $0 : nil }
    }

    /// Merge with another SnapPoints, deduplicating nearby edges
    func merged(with other: SnapPoints, tolerance: Int = 5) -> SnapPoints {
        var horizontal = Set(horizontalEdges)
        var vertical = Set(verticalEdges)

        for edge in other.horizontalEdges {
            if !horizontal.contains(where: { abs($0 - edge) <= tolerance }) {
                horizontal.insert(edge)
            }
        }

        for edge in other.verticalEdges {
            if !vertical.contains(where: { abs($0 - edge) <= tolerance }) {
                vertical.insert(edge)
            }
        }

        return SnapPoints(
            horizontalEdges: Array(horizontal).sorted(),
            verticalEdges: Array(vertical).sorted()
        )
    }

    static let empty = SnapPoints()
}

// MARK: - Rectangle & Edge Detector

/// Detects rectangles and edges in images using Vision framework for snap-to-edge functionality
struct RectangleDetector {

    /// Configuration for detection
    struct Configuration {
        // Rectangle detection settings
        var minimumAspectRatio: Float = 0.1
        var maximumAspectRatio: Float = 1.0
        var maximumObservations: Int = 20
        var minimumConfidence: Float = 0.15  // Lowered for better detection
        var quadratureTolerance: Float = 30.0
        var minimumSize: Float = 0.02

        // Contour detection settings
        var detectContours: Bool = true
        var contourMinimumLength: Int = 50  // Minimum contour length in pixels

        // Edge detection settings
        var detectEdges: Bool = true
        var edgeIntensity: Float = 1.0

        static let `default` = Configuration()

        /// Configuration optimized for UI screenshots
        static let screenshot = Configuration(
            minimumAspectRatio: 0.05,
            maximumAspectRatio: 1.0,
            maximumObservations: 25,
            minimumConfidence: 0.1,  // Very low to catch more rectangles
            quadratureTolerance: 35.0,
            minimumSize: 0.01,
            detectContours: true,
            contourMinimumLength: 30,
            detectEdges: true,
            edgeIntensity: 1.5
        )
    }

    // MARK: - Main Detection

    /// Detect all edges in an image using multiple methods
    static func detect(
        in image: NSImage,
        configuration: Configuration = .screenshot
    ) async -> SnapPoints {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .empty
        }

        return await detect(in: cgImage, configuration: configuration)
    }

    /// Detect all edges in a CGImage using multiple methods
    static func detect(
        in cgImage: CGImage,
        configuration: Configuration = .screenshot
    ) async -> SnapPoints {
        async let rectanglePoints = detectRectangles(in: cgImage, configuration: configuration)
        async let contourPoints = configuration.detectContours
            ? detectContours(in: cgImage, configuration: configuration)
            : SnapPoints.empty
        async let edgePoints = configuration.detectEdges
            ? detectEdges(in: cgImage, configuration: configuration)
            : SnapPoints.empty

        // Combine all detection results
        let rect = await rectanglePoints
        let contour = await contourPoints
        let edge = await edgePoints

        // Add image boundaries
        var result = rect.merged(with: contour).merged(with: edge)
        result.horizontalEdges.append(contentsOf: [0, cgImage.height])
        result.verticalEdges.append(contentsOf: [0, cgImage.width])
        result.horizontalEdges = Array(Set(result.horizontalEdges)).sorted()
        result.verticalEdges = Array(Set(result.verticalEdges)).sorted()

        return result
    }

    // MARK: - Rectangle Detection (VNDetectRectanglesRequest)

    private static func detectRectangles(
        in cgImage: CGImage,
        configuration: Configuration
    ) async -> SnapPoints {
        await withCheckedContinuation { continuation in
            let request = VNDetectRectanglesRequest { request, error in
                guard error == nil,
                      let results = request.results as? [VNRectangleObservation] else {
                    continuation.resume(returning: .empty)
                    return
                }

                let snapPoints = extractRectangleSnapPoints(
                    from: results,
                    imageWidth: cgImage.width,
                    imageHeight: cgImage.height,
                    minimumConfidence: configuration.minimumConfidence,
                    minimumSize: configuration.minimumSize
                )

                continuation.resume(returning: snapPoints)
            }

            request.minimumAspectRatio = configuration.minimumAspectRatio
            request.maximumAspectRatio = configuration.maximumAspectRatio
            request.maximumObservations = configuration.maximumObservations
            request.quadratureTolerance = configuration.quadratureTolerance

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: .empty)
            }
        }
    }

    // MARK: - Contour Detection (VNDetectContoursRequest)

    private static func detectContours(
        in cgImage: CGImage,
        configuration: Configuration
    ) async -> SnapPoints {
        await withCheckedContinuation { continuation in
            let request = VNDetectContoursRequest { request, error in
                guard error == nil,
                      let results = request.results as? [VNContoursObservation] else {
                    continuation.resume(returning: .empty)
                    return
                }

                let snapPoints = extractContourSnapPoints(
                    from: results,
                    imageWidth: cgImage.width,
                    imageHeight: cgImage.height,
                    minimumLength: configuration.contourMinimumLength
                )

                continuation.resume(returning: snapPoints)
            }

            // Detect more contours
            request.contrastAdjustment = 2.0
            request.detectsDarkOnLight = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: .empty)
            }
        }
    }

    // MARK: - Edge Detection (Core Image)

    private static func detectEdges(
        in cgImage: CGImage,
        configuration: Configuration
    ) async -> SnapPoints {
        let ciImage = CIImage(cgImage: cgImage)
        let context = CIContext()

        // Apply edge detection filter
        let edges = CIFilter.edges()
        edges.inputImage = ciImage
        edges.intensity = configuration.edgeIntensity

        guard let edgeImage = edges.outputImage,
              let edgeCGImage = context.createCGImage(edgeImage, from: edgeImage.extent) else {
            return .empty
        }

        // Analyze edge image to find strong horizontal/vertical lines
        return analyzeEdgeImage(edgeCGImage, originalWidth: cgImage.width, originalHeight: cgImage.height)
    }

    // MARK: - Snap Point Extraction

    private static func extractRectangleSnapPoints(
        from observations: [VNRectangleObservation],
        imageWidth: Int,
        imageHeight: Int,
        minimumConfidence: Float,
        minimumSize: Float
    ) -> SnapPoints {
        var horizontalEdges = Set<Int>()
        var verticalEdges = Set<Int>()

        let width = CGFloat(imageWidth)
        let height = CGFloat(imageHeight)

        for observation in observations {
            guard observation.confidence >= minimumConfidence else { continue }

            let topLeft = observation.topLeft
            let topRight = observation.topRight
            let bottomLeft = observation.bottomLeft
            let bottomRight = observation.bottomRight

            let minX = min(topLeft.x, bottomLeft.x)
            let maxX = max(topRight.x, bottomRight.x)
            let minY = min(bottomLeft.y, bottomRight.y)
            let maxY = max(topLeft.y, topRight.y)

            let rectWidth = maxX - minX
            let rectHeight = maxY - minY

            guard rectWidth >= CGFloat(minimumSize) && rectHeight >= CGFloat(minimumSize) else {
                continue
            }

            // Vision Y=0 is bottom, we want Y=0 at top
            let topEdge = Int((1.0 - maxY) * height)
            let bottomEdge = Int((1.0 - minY) * height)
            let leftEdge = Int(minX * width)
            let rightEdge = Int(maxX * width)

            addEdgeIfUnique(topEdge, to: &horizontalEdges, tolerance: 3)
            addEdgeIfUnique(bottomEdge, to: &horizontalEdges, tolerance: 3)
            addEdgeIfUnique(leftEdge, to: &verticalEdges, tolerance: 3)
            addEdgeIfUnique(rightEdge, to: &verticalEdges, tolerance: 3)
        }

        return SnapPoints(
            horizontalEdges: Array(horizontalEdges).sorted(),
            verticalEdges: Array(verticalEdges).sorted()
        )
    }

    private static func extractContourSnapPoints(
        from observations: [VNContoursObservation],
        imageWidth: Int,
        imageHeight: Int,
        minimumLength: Int
    ) -> SnapPoints {
        var horizontalEdges = Set<Int>()
        var verticalEdges = Set<Int>()

        let width = CGFloat(imageWidth)
        let height = CGFloat(imageHeight)

        for observation in observations {
            // Process top-level contours
            for i in 0..<observation.contourCount {
                guard let contour = try? observation.contour(at: i) else { continue }

                let points = contour.normalizedPoints
                guard points.count >= 2 else { continue }

                // Find horizontal and vertical segments in the contour
                for j in 0..<(points.count - 1) {
                    let p1 = points[j]
                    let p2 = points[j + 1]

                    let dx = abs(p2.x - p1.x)
                    let dy = abs(p2.y - p1.y)

                    // Check for horizontal segment (small dy, significant dx)
                    if dy < 0.01 && dx > 0.02 {
                        let y = Int((1.0 - CGFloat((p1.y + p2.y) / 2)) * height)
                        addEdgeIfUnique(y, to: &horizontalEdges, tolerance: 5)
                    }

                    // Check for vertical segment (small dx, significant dy)
                    if dx < 0.01 && dy > 0.02 {
                        let x = Int(CGFloat((p1.x + p2.x) / 2) * width)
                        addEdgeIfUnique(x, to: &verticalEdges, tolerance: 5)
                    }
                }
            }
        }

        return SnapPoints(
            horizontalEdges: Array(horizontalEdges).sorted(),
            verticalEdges: Array(verticalEdges).sorted()
        )
    }

    private static func analyzeEdgeImage(_ cgImage: CGImage, originalWidth: Int, originalHeight: Int) -> SnapPoints {
        var horizontalEdges = Set<Int>()
        var verticalEdges = Set<Int>()

        let width = cgImage.width
        let height = cgImage.height

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return .empty }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else { return .empty }
        let buffer = data.assumingMemoryBound(to: UInt8.self)

        // Scan for horizontal edges (rows with high edge density)
        let rowThreshold = Int(Double(width) * 0.15)  // 15% of row must be edge
        for y in stride(from: 0, to: height, by: 2) {
            var edgeCount = 0
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let brightness = Int(buffer[offset]) + Int(buffer[offset + 1]) + Int(buffer[offset + 2])
                if brightness > 100 {  // Edge detected
                    edgeCount += 1
                }
            }
            if edgeCount > rowThreshold {
                // Convert from edge image coords to original image coords
                let originalY = Int(Double(height - 1 - y) * Double(originalHeight) / Double(height))
                addEdgeIfUnique(originalY, to: &horizontalEdges, tolerance: 8)
            }
        }

        // Scan for vertical edges (columns with high edge density)
        let colThreshold = Int(Double(height) * 0.15)
        for x in stride(from: 0, to: width, by: 2) {
            var edgeCount = 0
            for y in 0..<height {
                let offset = (y * width + x) * 4
                let brightness = Int(buffer[offset]) + Int(buffer[offset + 1]) + Int(buffer[offset + 2])
                if brightness > 100 {
                    edgeCount += 1
                }
            }
            if edgeCount > colThreshold {
                let originalX = Int(Double(x) * Double(originalWidth) / Double(width))
                addEdgeIfUnique(originalX, to: &verticalEdges, tolerance: 8)
            }
        }

        return SnapPoints(
            horizontalEdges: Array(horizontalEdges).sorted(),
            verticalEdges: Array(verticalEdges).sorted()
        )
    }

    private static func addEdgeIfUnique(_ edge: Int, to edges: inout Set<Int>, tolerance: Int) {
        let hasSimilar = edges.contains { abs($0 - edge) <= tolerance }
        if !hasSimilar {
            edges.insert(edge)
        }
    }
}
