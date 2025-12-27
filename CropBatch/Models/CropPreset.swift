import Foundation

struct CropPreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var icon: String
    var cropSettings: CropSettings
    var isBuiltIn: Bool
    var category: PresetCategory
    var description: String?

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "crop",
        cropSettings: CropSettings,
        isBuiltIn: Bool = false,
        category: PresetCategory = .custom,
        description: String? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.cropSettings = cropSettings
        self.isBuiltIn = isBuiltIn
        self.category = category
        self.description = description
    }
}

enum PresetCategory: String, Codable, CaseIterable, Identifiable {
    case iPhone = "iPhone"
    case iPad = "iPad"
    case mac = "Mac"
    case browser = "Browser"
    case social = "Social Media"
    case custom = "Custom"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .iPhone: return "iphone"
        case .iPad: return "ipad"
        case .mac: return "desktopcomputer"
        case .browser: return "globe"
        case .social: return "square.and.arrow.up"
        case .custom: return "star"
        }
    }
}

// MARK: - Built-in Device Templates

extension CropPreset {

    /// Pre-built templates for common devices and use cases
    static let deviceTemplates: [CropPreset] = [
        // iPhone Templates
        CropPreset(
            name: "iPhone 15 Pro/Pro Max Status Bar",
            icon: "iphone",
            cropSettings: CropSettings(cropTop: 59, cropBottom: 0, cropLeft: 0, cropRight: 0),
            isBuiltIn: true,
            category: .iPhone,
            description: "Remove Dynamic Island status bar (59px)"
        ),
        CropPreset(
            name: "iPhone 15/14 Status Bar",
            icon: "iphone",
            cropSettings: CropSettings(cropTop: 47, cropBottom: 0, cropLeft: 0, cropRight: 0),
            isBuiltIn: true,
            category: .iPhone,
            description: "Remove notch status bar area (47px)"
        ),
        CropPreset(
            name: "iPhone Home Indicator",
            icon: "iphone",
            cropSettings: CropSettings(cropTop: 0, cropBottom: 34, cropLeft: 0, cropRight: 0),
            isBuiltIn: true,
            category: .iPhone,
            description: "Remove bottom home indicator (34px)"
        ),
        CropPreset(
            name: "iPhone Full Chrome",
            icon: "iphone",
            cropSettings: CropSettings(cropTop: 59, cropBottom: 34, cropLeft: 0, cropRight: 0),
            isBuiltIn: true,
            category: .iPhone,
            description: "Remove status bar + home indicator"
        ),

        // iPad Templates
        CropPreset(
            name: "iPad Status Bar",
            icon: "ipad",
            cropSettings: CropSettings(cropTop: 24, cropBottom: 0, cropLeft: 0, cropRight: 0),
            isBuiltIn: true,
            category: .iPad,
            description: "Remove iPad status bar (24px)"
        ),
        CropPreset(
            name: "iPad Home Indicator",
            icon: "ipad",
            cropSettings: CropSettings(cropTop: 0, cropBottom: 20, cropLeft: 0, cropRight: 0),
            isBuiltIn: true,
            category: .iPad,
            description: "Remove iPad home indicator (20px)"
        ),

        // Mac Templates
        CropPreset(
            name: "macOS Menu Bar",
            icon: "menubar.rectangle",
            cropSettings: CropSettings(cropTop: 25, cropBottom: 0, cropLeft: 0, cropRight: 0),
            isBuiltIn: true,
            category: .mac,
            description: "Remove macOS menu bar (25px @1x, 50px @2x)"
        ),
        CropPreset(
            name: "macOS Menu Bar (Retina)",
            icon: "menubar.rectangle",
            cropSettings: CropSettings(cropTop: 50, cropBottom: 0, cropLeft: 0, cropRight: 0),
            isBuiltIn: true,
            category: .mac,
            description: "Remove macOS menu bar on Retina (50px)"
        ),
        CropPreset(
            name: "macOS Window Title Bar",
            icon: "macwindow",
            cropSettings: CropSettings(cropTop: 28, cropBottom: 0, cropLeft: 0, cropRight: 0),
            isBuiltIn: true,
            category: .mac,
            description: "Remove standard window title bar (28px)"
        ),
        CropPreset(
            name: "macOS Window Shadow",
            icon: "shadow",
            cropSettings: CropSettings(cropTop: 20, cropBottom: 20, cropLeft: 20, cropRight: 20),
            isBuiltIn: true,
            category: .mac,
            description: "Remove window shadow (20px all sides)"
        ),
        CropPreset(
            name: "macOS Dock",
            icon: "dock.rectangle",
            cropSettings: CropSettings(cropTop: 0, cropBottom: 80, cropLeft: 0, cropRight: 0),
            isBuiltIn: true,
            category: .mac,
            description: "Remove Dock area (~80px)"
        ),

        // Browser Templates
        CropPreset(
            name: "Safari Tab Bar",
            icon: "safari",
            cropSettings: CropSettings(cropTop: 52, cropBottom: 0, cropLeft: 0, cropRight: 0),
            isBuiltIn: true,
            category: .browser,
            description: "Remove Safari compact tab bar (52px)"
        ),
        CropPreset(
            name: "Safari Full Chrome",
            icon: "safari",
            cropSettings: CropSettings(cropTop: 87, cropBottom: 0, cropLeft: 0, cropRight: 0),
            isBuiltIn: true,
            category: .browser,
            description: "Remove Safari tabs + address bar (87px)"
        ),
        CropPreset(
            name: "Chrome Tab Bar",
            icon: "globe",
            cropSettings: CropSettings(cropTop: 56, cropBottom: 0, cropLeft: 0, cropRight: 0),
            isBuiltIn: true,
            category: .browser,
            description: "Remove Chrome tab bar (56px)"
        ),
        CropPreset(
            name: "Chrome Full Chrome",
            icon: "globe",
            cropSettings: CropSettings(cropTop: 92, cropBottom: 0, cropLeft: 0, cropRight: 0),
            isBuiltIn: true,
            category: .browser,
            description: "Remove Chrome tabs + address bar (92px)"
        ),

        // Social Media Templates
        CropPreset(
            name: "Instagram Square (1:1)",
            icon: "square",
            cropSettings: CropSettings(cropTop: 0, cropBottom: 0, cropLeft: 0, cropRight: 0),
            isBuiltIn: true,
            category: .social,
            description: "Prepare for 1080×1080 (crop to square)"
        ),
        CropPreset(
            name: "YouTube Thumbnail (16:9)",
            icon: "play.rectangle",
            cropSettings: CropSettings(cropTop: 0, cropBottom: 0, cropLeft: 0, cropRight: 0),
            isBuiltIn: true,
            category: .social,
            description: "Prepare for 1280×720 (16:9 aspect)"
        ),
    ]

    /// Group templates by category
    static var templatesByCategory: [PresetCategory: [CropPreset]] {
        Dictionary(grouping: deviceTemplates, by: { $0.category })
    }
}
