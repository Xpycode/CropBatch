import Foundation

struct FileSizeEstimate {
    let originalTotal: Int64
    let estimatedTotal: Int64
    let percentage: Double
    let perImageEstimates: [(original: Int64, estimated: Int64)]

    var savings: Int64 {
        originalTotal - estimatedTotal
    }

    var savingsPercentage: Double {
        guard originalTotal > 0 else { return 0 }
        return Double(savings) / Double(originalTotal) * 100
    }
}

struct FileSizeEstimator {

    /// Estimates the output file sizes based on crop and export settings
    /// - Parameters:
    ///   - images: Source images with their file sizes
    ///   - cropSettings: Current crop settings
    ///   - exportSettings: Export format and quality settings
    /// - Returns: File size estimate with totals and per-image breakdown
    static func estimate(
        images: [ImageItem],
        cropSettings: CropSettings,
        exportSettings: ExportSettings
    ) -> FileSizeEstimate {
        var perImageEstimates: [(original: Int64, estimated: Int64)] = []
        var originalTotal: Int64 = 0
        var estimatedTotal: Int64 = 0

        for image in images {
            let originalSize = image.fileSize
            let estimated = estimateOutputSize(
                for: image,
                cropSettings: cropSettings,
                exportSettings: exportSettings
            )

            perImageEstimates.append((originalSize, estimated))
            originalTotal += originalSize
            estimatedTotal += estimated
        }

        let percentage = originalTotal > 0
            ? Double(estimatedTotal) / Double(originalTotal) * 100
            : 100

        return FileSizeEstimate(
            originalTotal: originalTotal,
            estimatedTotal: estimatedTotal,
            percentage: percentage,
            perImageEstimates: perImageEstimates
        )
    }

    /// Estimates output size for a single image
    private static func estimateOutputSize(
        for image: ImageItem,
        cropSettings: CropSettings,
        exportSettings: ExportSettings
    ) -> Int64 {
        let originalFileSize = image.fileSize
        guard originalFileSize > 0 else { return 0 }

        // 1. Calculate pixel reduction ratio from cropping
        let originalPixels = image.originalSize.width * image.originalSize.height
        let croppedSize = cropSettings.croppedSize(from: image.originalSize)
        let croppedPixels = croppedSize.width * croppedSize.height
        let pixelRatio = originalPixels > 0 ? croppedPixels / originalPixels : 1.0

        // 2. Determine output format
        let outputFormat: ExportFormat
        if exportSettings.preserveOriginalFormat {
            outputFormat = ExportFormat.allCases.first {
                $0.fileExtension == image.fileExtension ||
                (image.fileExtension == "jpeg" && $0 == .jpeg)
            } ?? exportSettings.format
        } else {
            outputFormat = exportSettings.format
        }

        // 3. Calculate format conversion factor
        let formatFactor = formatConversionFactor(
            from: image.fileExtension,
            to: outputFormat,
            quality: exportSettings.quality
        )

        // 4. Estimate final size
        let estimated = Double(originalFileSize) * pixelRatio * formatFactor

        return Int64(estimated)
    }

    /// Estimates the size change when converting between formats
    /// This is a rough heuristic based on typical compression ratios
    private static func formatConversionFactor(
        from sourceExt: String,
        to targetFormat: ExportFormat,
        quality: Double
    ) -> Double {
        let sourceIsLossy = ["jpg", "jpeg", "heic"].contains(sourceExt)
        let sourceIsPNG = sourceExt == "png"

        switch targetFormat {
        case .png:
            // PNG is lossless, typically larger than JPEG
            if sourceIsLossy {
                // Converting JPEG/HEIC to PNG usually increases size 3-5x
                return 3.5
            } else {
                // PNG to PNG, roughly same size
                return 1.0
            }

        case .jpeg:
            // JPEG compression depends heavily on quality
            let qualityFactor = 0.3 + (quality * 0.7)  // Maps 0-1 to 0.3-1.0

            if sourceIsPNG {
                // PNG to JPEG typically reduces size significantly
                return qualityFactor * 0.25  // PNG to JPEG at 100% ≈ 25% of PNG size
            } else if sourceIsLossy {
                // Re-encoding lossy format
                return qualityFactor * 0.9  // Slight reduction possible
            } else {
                return qualityFactor * 0.3
            }

        case .heic:
            // HEIC is typically more efficient than JPEG
            let qualityFactor = 0.25 + (quality * 0.75)

            if sourceIsPNG {
                return qualityFactor * 0.15  // Very good compression
            } else if sourceIsLossy {
                return qualityFactor * 0.7
            } else {
                return qualityFactor * 0.2
            }

        case .tiff:
            // TIFF is typically uncompressed or lightly compressed
            if sourceIsLossy {
                return 4.0  // Decompressing to TIFF increases size
            } else {
                return 1.1  // Similar to PNG
            }
        }
    }
}

// MARK: - Formatting Helpers

extension Int64 {
    /// Formats bytes as human-readable string (KB, MB, GB)
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: self)
    }
}
