import SwiftUI

struct PresetPickerView: View {
    @Environment(AppState.self) private var appState
    @State private var presetManager = PresetManager.shared
    @State private var searchText = ""
    @State private var selectedCategory: PresetCategory?
    @State private var showSaveSheet = false
    @State private var newPresetName = ""

    private var filteredPresets: [CropPreset] {
        var presets = presetManager.allPresets

        // Filter by category
        if let category = selectedCategory {
            presets = presets.filter { $0.category == category }
        }

        // Filter by search
        if !searchText.isEmpty {
            presets = presets.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                ($0.description?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        return presets
    }

    private var recentPresets: [CropPreset] {
        appState.recentPresetIDs.compactMap { id in
            presetManager.allPresets.first { $0.id == id }
        }
    }

    private var showRecentSection: Bool {
        !recentPresets.isEmpty && searchText.isEmpty && selectedCategory == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with save button
            HStack {
                Text("Crop Presets")
                    .font(.headline)

                Spacer()

                Button {
                    newPresetName = "My Preset"
                    showSaveSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(!appState.cropSettings.hasAnyCrop)
                .help("Save current crop as preset")
            }

            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search presets...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))

            // Category filter dropdown
            HStack {
                Text("Category")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer()

                Menu {
                    Button {
                        selectedCategory = nil
                    } label: {
                        Label("All Categories", systemImage: "square.grid.2x2")
                    }

                    Divider()

                    ForEach(PresetCategory.allCases) { category in
                        Button {
                            selectedCategory = category
                        } label: {
                            Label(category.rawValue, systemImage: category.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if let category = selectedCategory {
                            Image(systemName: category.icon)
                                .font(.caption)
                            Text(category.rawValue)
                        } else {
                            Image(systemName: "square.grid.2x2")
                                .font(.caption)
                            Text("All")
                        }
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                }
                .buttonStyle(.plain)
            }

            // Presets list
            ScrollView {
                LazyVStack(spacing: 4) {
                    // Recent section
                    if showRecentSection {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.caption)
                            Text("Recent")
                                .font(.caption.weight(.medium))
                            Spacer()
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)

                        ForEach(recentPresets) { preset in
                            PresetRowView(preset: preset) {
                                applyPreset(preset)
                            }
                        }

                        Divider()
                            .padding(.vertical, 4)
                    }

                    // All presets
                    ForEach(filteredPresets) { preset in
                        PresetRowView(preset: preset) {
                            applyPreset(preset)
                        }
                    }

                    if filteredPresets.isEmpty {
                        Text("No presets found")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .sheet(isPresented: $showSaveSheet) {
            SavePresetSheet(
                presetName: $newPresetName,
                cropSettings: appState.cropSettings
            ) {
                showSaveSheet = false
            }
        }
    }

    private func applyPreset(_ preset: CropPreset) {
        appState.cropSettings = preset.cropSettings
        appState.trackRecentPreset(preset.id)
        appState.recordCropChange()
    }
}

// MARK: - Preset Row

struct PresetRowView: View {
    let preset: CropPreset
    let onApply: () -> Void
    @State private var presetManager = PresetManager.shared
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            // Icon
            Image(systemName: preset.icon)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            // Name and description
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(preset.name)
                        .font(.callout)
                        .lineLimit(1)

                    if preset.isBuiltIn {
                        Text("Built-in")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.gray.opacity(0.2)))
                    }
                }

                if let description = preset.description {
                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Crop values preview
            Text(cropValuesPreview)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)

            // Apply button
            if isHovering {
                Button("Apply", action: onApply)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture(count: 2) {
            onApply()
        }
        .contextMenu {
            Button("Apply Preset") {
                onApply()
            }

            Button("Duplicate") {
                _ = presetManager.duplicatePreset(preset)
            }

            if !preset.isBuiltIn {
                Divider()
                Button("Delete", role: .destructive) {
                    presetManager.deletePreset(preset)
                }
            }
        }
    }

    private var cropValuesPreview: String {
        let s = preset.cropSettings
        var parts: [String] = []
        if s.cropTop > 0 { parts.append("T:\(s.cropTop)") }
        if s.cropBottom > 0 { parts.append("B:\(s.cropBottom)") }
        if s.cropLeft > 0 { parts.append("L:\(s.cropLeft)") }
        if s.cropRight > 0 { parts.append("R:\(s.cropRight)") }
        return parts.isEmpty ? "No crop" : parts.joined(separator: " ")
    }
}

// MARK: - Save Preset Sheet

struct SavePresetSheet: View {
    @Binding var presetName: String
    let cropSettings: CropSettings
    let onDismiss: () -> Void
    @State private var presetManager = PresetManager.shared
    @State private var selectedIcon = "crop"

    private let iconOptions = [
        "crop", "crop.rotate", "aspectratio", "rectangle.portrait.crop",
        "photo", "camera", "doc", "folder", "star", "bookmark"
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text("Save Crop Preset")
                .font(.headline)

            // Name field
            TextField("Preset name", text: $presetName)
                .textFieldStyle(.roundedBorder)

            // Icon picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Icon")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(iconOptions, id: \.self) { icon in
                        Button {
                            selectedIcon = icon
                        } label: {
                            Image(systemName: icon)
                                .font(.title3)
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedIcon == icon ? Color.accentColor : Color.clear)
                                )
                                .foregroundStyle(selectedIcon == icon ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Crop values preview
            VStack(alignment: .leading, spacing: 4) {
                Text("Crop Values")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    CropValueLabel(edge: "Top", value: cropSettings.cropTop)
                    CropValueLabel(edge: "Bottom", value: cropSettings.cropBottom)
                    CropValueLabel(edge: "Left", value: cropSettings.cropLeft)
                    CropValueLabel(edge: "Right", value: cropSettings.cropRight)
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))

            // Buttons
            HStack {
                Button("Cancel", role: .cancel) {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    presetManager.savePreset(
                        name: presetName,
                        cropSettings: cropSettings,
                        icon: selectedIcon
                    )
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(presetName.isEmpty)
            }
        }
        .padding()
        .frame(width: 350)
    }
}

struct CropValueLabel: View {
    let edge: String
    let value: Int

    var body: some View {
        VStack(spacing: 2) {
            Text(edge)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(value)px")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
    }
}

#Preview {
    PresetPickerView()
        .environment(AppState())
        .frame(width: 300)
        .padding()
}
