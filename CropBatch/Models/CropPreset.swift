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
    case windows = "Windows"
    case browser = "Browser"
    case custom = "Custom"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .iPhone: return "iphone"
        case .iPad: return "ipad"
        case .mac: return "desktopcomputer"
        case .windows: return "pc"
        case .browser: return "globe"
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

        // Windows Templates
        CropPreset(
            name: "Windows 11 Title Bar",
            icon: "pc",
            cropSettings: CropSettings(cropTop: 32, cropBottom: 0, cropLeft: 0, cropRight: 0),
            isBuiltIn: true,
            category: .windows,
            description: "Remove Windows 11 window title bar (32px)"
        ),
        CropPreset(
            name: "Windows 10 Title Bar",
            icon: "pc",
            cropSettings: CropSettings(cropTop: 30, cropBottom: 0, cropLeft: 0, cropRight: 0),
            isBuiltIn: true,
            category: .windows,
            description: "Remove Windows 10 window title bar (30px)"
        ),
        CropPreset(
            name: "Windows 11 Taskbar",
            icon: "pc",
            cropSettings: CropSettings(cropTop: 0, cropBottom: 48, cropLeft: 0, cropRight: 0),
            isBuiltIn: true,
            category: .windows,
            description: "Remove Windows 11 taskbar (48px)"
        ),
        CropPreset(
            name: "Windows 10 Taskbar",
            icon: "pc",
            cropSettings: CropSettings(cropTop: 0, cropBottom: 40, cropLeft: 0, cropRight: 0),
            isBuiltIn: true,
            category: .windows,
            description: "Remove Windows 10 taskbar (40px)"
        ),
        CropPreset(
            name: "Windows Full Chrome",
            icon: "pc",
            cropSettings: CropSettings(cropTop: 32, cropBottom: 48, cropLeft: 0, cropRight: 0),
            isBuiltIn: true,
            category: .windows,
            description: "Remove title bar + taskbar (Win 11)"
        ),
        CropPreset(
            name: "Windows Window Border",
            icon: "pc",
            cropSettings: CropSettings(cropTop: 1, cropBottom: 1, cropLeft: 1, cropRight: 1),
            isBuiltIn: true,
            category: .windows,
            description: "Remove 1px window border"
        ),

        // Browser Templates - Safari
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

        // Browser Templates - Chrome
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

        // Browser Templates - Firefox
        CropPreset(
            name: "Firefox Tab Bar",
            icon: "flame",
            cropSettings: CropSettings(cropTop: 45, cropBottom: 0, cropLeft: 0, cropRight: 0),
            isBuiltIn: true,
            category: .browser,
            description: "Remove Firefox tab bar (45px)"
        ),
        CropPreset(
            name: "Firefox Full Chrome",
            icon: "flame",
            cropSettings: CropSettings(cropTop: 85, cropBottom: 0, cropLeft: 0, cropRight: 0),
            isBuiltIn: true,
            category: .browser,
            description: "Remove Firefox tabs + address bar (85px)"
        ),

        // Browser Templates - Edge
        CropPreset(
            name: "Edge Tab Bar",
            icon: "globe",
            cropSettings: CropSettings(cropTop: 56, cropBottom: 0, cropLeft: 0, cropRight: 0),
            isBuiltIn: true,
            category: .browser,
            description: "Remove Edge tab bar (56px)"
        ),
        CropPreset(
            name: "Edge Full Chrome",
            icon: "globe",
            cropSettings: CropSettings(cropTop: 90, cropBottom: 0, cropLeft: 0, cropRight: 0),
            isBuiltIn: true,
            category: .browser,
            description: "Remove Edge tabs + address bar (90px)"
        ),

        // Browser Templates - Arc
        CropPreset(
            name: "Arc Sidebar",
            icon: "sidebar.left",
            cropSettings: CropSettings(cropTop: 0, cropBottom: 0, cropLeft: 70, cropRight: 0),
            isBuiltIn: true,
            category: .browser,
            description: "Remove Arc sidebar (70px)"
        ),
        CropPreset(
            name: "Arc Full Chrome",
            icon: "sidebar.left",
            cropSettings: CropSettings(cropTop: 44, cropBottom: 0, cropLeft: 70, cropRight: 0),
            isBuiltIn: true,
            category: .browser,
            description: "Remove Arc sidebar + top bar"
        ),

        // Browser Templates - Brave
        CropPreset(
            name: "Brave Tab Bar",
            icon: "shield",
            cropSettings: CropSettings(cropTop: 56, cropBottom: 0, cropLeft: 0, cropRight: 0),
            isBuiltIn: true,
            category: .browser,
            description: "Remove Brave tab bar (56px)"
        ),
        CropPreset(
            name: "Brave Full Chrome",
            icon: "shield",
            cropSettings: CropSettings(cropTop: 92, cropBottom: 0, cropLeft: 0, cropRight: 0),
            isBuiltIn: true,
            category: .browser,
            description: "Remove Brave tabs + address bar (92px)"
        ),
    ]

    /// Group templates by category
    static var templatesByCategory: [PresetCategory: [CropPreset]] {
        Dictionary(grouping: deviceTemplates, by: { $0.category })
    }
}
