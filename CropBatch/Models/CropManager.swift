import SwiftUI

/// Manages crop settings, undo/redo history, and presets
@Observable
final class CropManager {
    // MARK: - Crop Settings

    var settings = CropSettings()

    // MARK: - Undo/Redo History

    private var history: [CropSettings] = [CropSettings()]
    private var historyIndex: Int = 0
    private var isUndoRedoAction = false

    var canUndo: Bool { historyIndex > 0 }
    var canRedo: Bool { historyIndex < history.count - 1 }

    // MARK: - Edge Linking

    var edgeLinkMode: EdgeLinkMode = .none

    // MARK: - Aspect Ratio Guide

    var showAspectRatioGuide: AspectRatioGuide? = nil

    // MARK: - Recent Presets

    var recentPresetIDs: [UUID] = []
    private let recentPresetsKey = "CropBatch.RecentPresetIDs"

    // MARK: - Initialization

    init() {
        loadRecentPresets()
    }

    // MARK: - History Management

    /// Record current crop settings in history
    func recordChange() {
        guard !isUndoRedoAction else { return }

        // Remove any redo history
        if historyIndex < history.count - 1 {
            history.removeSubrange((historyIndex + 1)...)
        }

        history.append(settings)
        historyIndex = history.count - 1

        // Limit history size
        if history.count > Config.History.maxUndoSteps {
            history.removeFirst()
            historyIndex -= 1
        }
    }

    /// Undo last crop change
    func undo() {
        guard canUndo else { return }
        isUndoRedoAction = true
        historyIndex -= 1
        settings = history[historyIndex]
        isUndoRedoAction = false
    }

    /// Redo previously undone crop change
    func redo() {
        guard canRedo else { return }
        isUndoRedoAction = true
        historyIndex += 1
        settings = history[historyIndex]
        isUndoRedoAction = false
    }

    /// Reset all crops
    func reset() {
        settings = CropSettings()
        recordChange()
    }

    // MARK: - Crop Adjustments

    func adjustCrop(edge: CropEdge, delta: Int, maxWidth: Int, maxHeight: Int) {
        switch edge {
        case .top:
            let newValue = settings.cropTop + delta
            settings.cropTop = max(0, min(newValue, maxHeight - settings.cropBottom - 10))
        case .bottom:
            let newValue = settings.cropBottom + delta
            settings.cropBottom = max(0, min(newValue, maxHeight - settings.cropTop - 10))
        case .left:
            let newValue = settings.cropLeft + delta
            settings.cropLeft = max(0, min(newValue, maxWidth - settings.cropRight - 10))
        case .right:
            let newValue = settings.cropRight + delta
            settings.cropRight = max(0, min(newValue, maxWidth - settings.cropLeft - 10))
        }
    }

    /// Validates and clamps crop values to ensure they don't exceed image dimensions
    func validateAndClamp(maxWidth: Int, maxHeight: Int) {
        // Clamp each edge, ensuring at least 1 pixel remains after cropping
        settings.cropLeft = min(max(0, settings.cropLeft), maxWidth - settings.cropRight - 1)
        settings.cropRight = min(max(0, settings.cropRight), maxWidth - settings.cropLeft - 1)
        settings.cropTop = min(max(0, settings.cropTop), maxHeight - settings.cropBottom - 1)
        settings.cropBottom = min(max(0, settings.cropBottom), maxHeight - settings.cropTop - 1)
    }

    // MARK: - Presets

    /// Apply a crop preset with undo support
    func applyPreset(_ preset: CropPreset) {
        settings = preset.cropSettings
        trackRecentPreset(preset.id)
        recordChange()
    }

    /// Track a preset as recently used
    func trackRecentPreset(_ presetID: UUID) {
        // Remove if already exists (to move to front)
        recentPresetIDs.removeAll { $0 == presetID }
        // Insert at front
        recentPresetIDs.insert(presetID, at: 0)
        // Keep only recent presets up to limit
        if recentPresetIDs.count > Config.Presets.recentLimit {
            recentPresetIDs = Array(recentPresetIDs.prefix(Config.Presets.recentLimit))
        }
        // Persist
        let strings = recentPresetIDs.map { $0.uuidString }
        UserDefaults.standard.set(strings, forKey: recentPresetsKey)
    }

    /// Load recent presets from UserDefaults
    private func loadRecentPresets() {
        guard let strings = UserDefaults.standard.stringArray(forKey: recentPresetsKey) else { return }
        recentPresetIDs = strings.compactMap { UUID(uuidString: $0) }
    }
}
