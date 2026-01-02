import Foundation

@MainActor
@Observable
final class PresetManager {
    static let shared = PresetManager()

    private let userDefaultsKey = "CropBatch.UserPresets"

    /// User-created presets (persisted)
    private(set) var userPresets: [CropPreset] = []

    /// Last error encountered during load/save operations
    var lastError: Error?

    /// Clears the current error state
    func clearError() {
        lastError = nil
    }

    /// All presets (built-in + user)
    var allPresets: [CropPreset] {
        CropPreset.deviceTemplates + userPresets
    }

    /// Presets grouped by category
    var presetsByCategory: [PresetCategory: [CropPreset]] {
        Dictionary(grouping: allPresets, by: { $0.category })
    }

    private init() {
        loadUserPresets()
    }

    // MARK: - Preset Management

    /// Save current crop settings as a new preset
    func savePreset(name: String, cropSettings: CropSettings, icon: String = "crop") {
        let preset = CropPreset(
            name: name,
            icon: icon,
            cropSettings: cropSettings,
            isBuiltIn: false,
            category: .custom
        )
        userPresets.append(preset)
        persistUserPresets()
    }

    /// Update an existing user preset
    func updatePreset(_ preset: CropPreset, newSettings: CropSettings) {
        guard let index = userPresets.firstIndex(where: { $0.id == preset.id }) else { return }
        userPresets[index].cropSettings = newSettings
        persistUserPresets()
    }

    /// Rename a user preset
    func renamePreset(_ preset: CropPreset, newName: String) {
        guard let index = userPresets.firstIndex(where: { $0.id == preset.id }) else { return }
        userPresets[index].name = newName
        persistUserPresets()
    }

    /// Delete a user preset
    func deletePreset(_ preset: CropPreset) {
        guard !preset.isBuiltIn else { return }  // Can't delete built-in presets
        userPresets.removeAll { $0.id == preset.id }
        persistUserPresets()
    }

    /// Duplicate a preset (built-in or user)
    func duplicatePreset(_ preset: CropPreset) -> CropPreset {
        let newPreset = CropPreset(
            name: "\(preset.name) Copy",
            icon: preset.icon,
            cropSettings: preset.cropSettings,
            isBuiltIn: false,
            category: .custom
        )
        userPresets.append(newPreset)
        persistUserPresets()
        return newPreset
    }

    // MARK: - Persistence

    private func loadUserPresets() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return }
        do {
            userPresets = try JSONDecoder().decode([CropPreset].self, from: data)
            lastError = nil
        } catch {
            lastError = error
        }
    }

    private func persistUserPresets() {
        do {
            let data = try JSONEncoder().encode(userPresets)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            lastError = nil
        } catch {
            lastError = error
        }
    }

    // MARK: - Search & Filter

    /// Find presets matching a search query
    func search(_ query: String) -> [CropPreset] {
        guard !query.isEmpty else { return allPresets }
        let lowercased = query.lowercased()
        return allPresets.filter {
            $0.name.lowercased().contains(lowercased) ||
            ($0.description?.lowercased().contains(lowercased) ?? false)
        }
    }

    /// Get presets for a specific category
    func presets(for category: PresetCategory) -> [CropPreset] {
        allPresets.filter { $0.category == category }
    }
}
