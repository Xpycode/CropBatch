import Foundation
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable, Codable {
    case png = "PNG"
    case jpeg = "JPEG"
    case heic = "HEIC"
    case tiff = "TIFF"
    case webp = "WebP"

    var id: String { rawValue }

    var utType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .heic: return .heic
        case .tiff: return .tiff
        case .webp: return .webP
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .heic: return "heic"
        case .tiff: return "tiff"
        case .webp: return "webp"
        }
    }

    var supportsCompression: Bool {
        switch self {
        case .jpeg, .heic, .webp: return true
        case .png, .tiff: return false
        }
    }
}

/// Resize mode options
enum ResizeMode: String, CaseIterable, Identifiable, Codable {
    case none = "None"
    case exactSize = "Exact Size"
    case maxWidth = "Max Width"
    case maxHeight = "Max Height"
    case percentage = "Percentage"

    var id: String { rawValue }
}

/// Resize settings for output images
struct ResizeSettings: Equatable, Codable {
    var mode: ResizeMode = .none
    var width: Int = 1920
    var height: Int = 1080
    var percentage: Double = 50.0
    var maintainAspectRatio: Bool = true

    var isEnabled: Bool {
        mode != .none
    }
}

/// Rename mode for batch export
enum RenameMode: String, CaseIterable, Identifiable, Codable {
    case keepOriginal = "Keep Original"
    case pattern = "Pattern"

    var id: String { rawValue }
}

/// Settings for batch rename on export
struct RenameSettings: Equatable, Codable {
    var mode: RenameMode = .keepOriginal
    var pattern: String = "{name}_{counter}"
    var startIndex: Int = 1
    var zeroPadding: Int = 2  // 01, 02, ... 99

    static let `default` = RenameSettings()

    /// Available tokens for pattern replacement
    static let availableTokens: [(token: String, description: String)] = [
        ("{name}", "Original filename"),
        ("{counter}", "Padded counter (01, 02...)"),
        ("{index}", "Position in batch (1, 2...)"),
        ("{date}", "Current date (YYYY-MM-DD)"),
        ("{time}", "Current time (HH-MM-SS)")
    ]

    /// Preview of what the pattern will produce
    func preview(originalName: String = "screenshot", index: Int = 0) -> String {
        processPattern(originalName: originalName, index: index)
    }

    /// Process the pattern with actual values
    func processPattern(originalName: String, index: Int) -> String {
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: now)
        dateFormatter.dateFormat = "HH-mm-ss"
        let timeString = dateFormatter.string(from: now)

        let paddedCounter = String(format: "%0\(zeroPadding)d", startIndex + index)

        var result = pattern
        result = result.replacingOccurrences(of: "{name}", with: originalName)
        result = result.replacingOccurrences(of: "{counter}", with: paddedCounter)
        result = result.replacingOccurrences(of: "{index}", with: "\(index + 1)")
        result = result.replacingOccurrences(of: "{date}", with: dateString)
        result = result.replacingOccurrences(of: "{time}", with: timeString)

        return result
    }
}

struct ExportSettings: Equatable {
    var format: ExportFormat = .png
    var quality: Double = 0.9  // 0.0 to 1.0, only for JPEG/HEIC
    var suffix: String = "_cropped"
    var preserveOriginalFormat: Bool = false
    var outputDirectory: OutputDirectory = .sameAsSource
    var resizeSettings: ResizeSettings = ResizeSettings()
    var renameSettings: RenameSettings = RenameSettings()
    var watermarkSettings: WatermarkSettings = WatermarkSettings()

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

    /// Generates the output URL for a given input URL (without index, uses suffix mode)
    func outputURL(for inputURL: URL) -> URL {
        outputURL(for: inputURL, index: 0)
    }

    /// Generates the output URL for a given input URL with batch index
    func outputURL(for inputURL: URL, index: Int) -> URL {
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

        // Build new filename based on rename mode
        let baseName: String
        if renameSettings.mode == .pattern {
            baseName = renameSettings.processPattern(originalName: originalName, index: index)
        } else {
            baseName = "\(originalName)\(suffix)"
        }

        let newFilename = "\(baseName).\(outputFormat.fileExtension)"

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

    /// Generates just the output filename (without directory) for a given input URL
    func outputFilename(for inputURL: URL, index: Int = 0) -> String {
        outputURL(for: inputURL, index: index).lastPathComponent
    }

    /// Validates that no filename collisions exist in batch export
    /// - Parameter items: The items to be exported
    /// - Returns: nil if no collisions, otherwise the first colliding filename
    func findBatchCollision(items: [ImageItem]) -> String? {
        var plannedURLs = Set<URL>()

        for (index, item) in items.enumerated() {
            let destURL = outputURL(for: item.url, index: index)

            if plannedURLs.contains(destURL) {
                return destURL.lastPathComponent
            }
            plannedURLs.insert(destURL)
        }

        return nil
    }

    /// Finds files that would be overwritten during export
    /// - Parameter items: The items to be exported
    /// - Returns: Array of (index, URL) for files that already exist
    func findExistingFiles(items: [ImageItem]) -> [(index: Int, url: URL)] {
        let fileManager = FileManager.default
        var existing: [(Int, URL)] = []

        for (index, item) in items.enumerated() {
            let destURL = outputURL(for: item.url, index: index)
            if fileManager.fileExists(atPath: destURL.path) {
                existing.append((index, destURL))
            }
        }

        return existing
    }

    /// Creates a new filename with a numeric suffix to avoid collision
    /// e.g., "photo_cropped.jpg" -> "photo_cropped_1.jpg"
    static func appendNumericSuffix(to url: URL, startingAt: Int = 1) -> URL {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        let filename = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        var counter = startingAt
        var newURL: URL

        repeat {
            let newFilename = "\(filename)_\(counter).\(ext)"
            newURL = directory.appendingPathComponent(newFilename)
            counter += 1
        } while fileManager.fileExists(atPath: newURL.path)

        return newURL
    }
}

// MARK: - Overwrite Handling

/// User's choice when existing files are detected
enum OverwriteChoice {
    case overwrite      // Replace existing files
    case rename         // Append _1, _2, etc. to avoid collision
    case cancel         // Abort the export
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
            id: "webp_high",
            name: "WebP High (90%)",
            icon: "globe",
            settings: ExportSettings(format: .webp, quality: 0.9, suffix: "_cropped")
        ),
        ExportPreset(
            id: "webp_web",
            name: "WebP Web (75%)",
            icon: "network",
            settings: ExportSettings(format: .webp, quality: 0.75, suffix: "_cropped")
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

// MARK: - User Export Profiles

struct UserExportProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var settings: ExportSettingsCodable

    init(id: UUID = UUID(), name: String, settings: ExportSettings) {
        self.id = id
        self.name = name
        self.settings = ExportSettingsCodable(from: settings)
    }

    var exportSettings: ExportSettings {
        settings.toExportSettings()
    }
}

/// Codable wrapper for ExportSettings (since OutputDirectory can't easily be Codable)
struct ExportSettingsCodable: Codable, Equatable {
    var format: ExportFormat
    var quality: Double
    var suffix: String
    var preserveOriginalFormat: Bool
    var resizeSettings: ResizeSettings
    var renameSettings: RenameSettings

    init(from settings: ExportSettings) {
        self.format = settings.format
        self.quality = settings.quality
        self.suffix = settings.suffix
        self.preserveOriginalFormat = settings.preserveOriginalFormat
        self.resizeSettings = settings.resizeSettings
        self.renameSettings = settings.renameSettings
    }

    func toExportSettings() -> ExportSettings {
        ExportSettings(
            format: format,
            quality: quality,
            suffix: suffix,
            preserveOriginalFormat: preserveOriginalFormat,
            resizeSettings: resizeSettings,
            renameSettings: renameSettings
        )
    }
}

@MainActor
@Observable
final class ExportProfileManager {
    static let shared = ExportProfileManager()

    private let userDefaultsKey = "CropBatch.UserExportProfiles"

    private(set) var userProfiles: [UserExportProfile] = []

    private init() {
        loadProfiles()
    }

    func saveProfile(name: String, settings: ExportSettings) {
        let profile = UserExportProfile(name: name, settings: settings)
        userProfiles.append(profile)
        persist()
    }

    func deleteProfile(_ profile: UserExportProfile) {
        userProfiles.removeAll { $0.id == profile.id }
        persist()
    }

    func renameProfile(_ profile: UserExportProfile, to newName: String) {
        guard let index = userProfiles.firstIndex(where: { $0.id == profile.id }) else { return }
        userProfiles[index].name = newName
        persist()
    }

    private func loadProfiles() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return }
        do {
            userProfiles = try JSONDecoder().decode([UserExportProfile].self, from: data)
        } catch {
            print("Failed to load export profiles: \(error)")
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(userProfiles)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            print("Failed to save export profiles: \(error)")
        }
    }
}
