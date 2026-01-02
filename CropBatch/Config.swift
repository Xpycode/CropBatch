import Foundation

/// Centralized configuration constants for the app
enum Config {
    // MARK: - History / Undo
    enum History {
        /// Maximum number of undo steps to keep
        static let maxUndoSteps = 50
    }

    // MARK: - Memory Management
    enum Memory {
        /// Number of images that triggers a memory warning
        static let imageCountWarningThreshold = 50
        /// Number of images that triggers a critical memory warning
        static let imageCountCriticalThreshold = 100
    }

    // MARK: - Blur Tool
    enum Blur {
        /// Minimum size for a blur region (as fraction of image dimension)
        static let minimumRegionSize = 0.02
    }

    // MARK: - Thumbnail Cache
    enum Cache {
        /// Maximum number of thumbnails to keep in memory
        static let thumbnailCountLimit = 100
        /// Maximum total memory for cached thumbnails (50MB)
        static let thumbnailSizeLimit = 50 * 1024 * 1024
    }

    // MARK: - Snap Points
    enum Snap {
        /// Default threshold in pixels for edge snapping
        static let defaultThreshold = 15
    }

    // MARK: - Presets
    enum Presets {
        /// Maximum number of recent presets to track
        static let recentLimit = 5
    }
}
