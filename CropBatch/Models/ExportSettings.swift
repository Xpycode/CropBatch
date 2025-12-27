import Foundation
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable, Codable {
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

    /// Generates just the output filename (without directory) for a given input URL
    func outputFilename(for inputURL: URL) -> String {
        outputURL(for: inputURL).lastPathComponent
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

    init(from settings: ExportSettings) {
        self.format = settings.format
        self.quality = settings.quality
        self.suffix = settings.suffix
        self.preserveOriginalFormat = settings.preserveOriginalFormat
    }

    func toExportSettings() -> ExportSettings {
        ExportSettings(
            format: format,
            quality: quality,
            suffix: suffix,
            preserveOriginalFormat: preserveOriginalFormat
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
