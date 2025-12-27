import Foundation
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case png = "PNG"
    case jpeg = "JPEG"
    case heic = "HEIC"
    case tiff = "TIFF"

    var id: String { rawValue }

    var utType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .heic: return .heic
        case .tiff: return .tiff
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .heic: return "heic"
        case .tiff: return "tiff"
        }
    }

    var supportsCompression: Bool {
        switch self {
        case .jpeg, .heic: return true
        case .png, .tiff: return false
        }
    }
}

struct ExportSettings: Equatable {
    var format: ExportFormat = .png
    var quality: Double = 0.9  // 0.0 to 1.0, only for JPEG/HEIC
    var suffix: String = "_cropped"
    var preserveOriginalFormat: Bool = false
    var outputDirectory: OutputDirectory = .sameAsSource

    enum OutputDirectory: Equatable {
        case sameAsSource
        case custom(URL)

        var displayName: String {
            switch self {
            case .sameAsSource: return "Same as original"
            case .custom(let url): return url.lastPathComponent
            }
        }
    }

    /// Generates the output filename for a given input URL
    func outputURL(for inputURL: URL) -> URL {
        let originalName = inputURL.deletingPathExtension().lastPathComponent
        let originalExtension = inputURL.pathExtension.lowercased()

        // Determine output format
        let outputFormat: ExportFormat
        if preserveOriginalFormat {
            outputFormat = ExportFormat.allCases.first {
                $0.fileExtension == originalExtension ||
                (originalExtension == "jpeg" && $0 == .jpeg)
            } ?? format
        } else {
            outputFormat = format
        }

        // Build new filename
        let newFilename = "\(originalName)\(suffix).\(outputFormat.fileExtension)"

        // Determine output directory
        let outputDir: URL
        switch outputDirectory {
        case .sameAsSource:
            outputDir = inputURL.deletingLastPathComponent()
        case .custom(let url):
            outputDir = url
        }

        return outputDir.appendingPathComponent(newFilename)
    }

    /// Checks if the output would overwrite the original
    func wouldOverwriteOriginal(for inputURL: URL) -> Bool {
        return outputURL(for: inputURL) == inputURL
    }
}

// MARK: - Presets

struct ExportPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    let settings: ExportSettings

    static let presets: [ExportPreset] = [
        ExportPreset(
            id: "png_lossless",
            name: "PNG Lossless",
            icon: "doc.zipper",
            settings: ExportSettings(format: .png, suffix: "_cropped")
        ),
        ExportPreset(
            id: "jpeg_high",
            name: "JPEG High (90%)",
            icon: "photo",
            settings: ExportSettings(format: .jpeg, quality: 0.9, suffix: "_cropped")
        ),
        ExportPreset(
            id: "jpeg_medium",
            name: "JPEG Medium (75%)",
            icon: "photo",
            settings: ExportSettings(format: .jpeg, quality: 0.75, suffix: "_cropped")
        ),
        ExportPreset(
            id: "jpeg_web",
            name: "JPEG Web (60%)",
            icon: "globe",
            settings: ExportSettings(format: .jpeg, quality: 0.6, suffix: "_cropped")
        ),
        ExportPreset(
            id: "heic_high",
            name: "HEIC High (90%)",
            icon: "apple.logo",
            settings: ExportSettings(format: .heic, quality: 0.9, suffix: "_cropped")
        ),
        ExportPreset(
            id: "preserve_format",
            name: "Keep Original Format",
            icon: "arrow.triangle.2.circlepath",
            settings: ExportSettings(suffix: "_cropped", preserveOriginalFormat: true)
        )
    ]

    static func == (lhs: ExportPreset, rhs: ExportPreset) -> Bool {
        lhs.id == rhs.id
    }
}
