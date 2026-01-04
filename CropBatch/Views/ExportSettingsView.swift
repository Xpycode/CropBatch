import SwiftUI

struct ExportSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        VStack(alignment: .leading, spacing: 12) {
            // Preset picker
            PresetPicker()

            Divider()

            // Format picker (only if not preserving original)
            if !appState.exportSettings.preserveOriginalFormat {
                FormatPicker(format: Binding(
                    get: { appState.exportSettings.format },
                    set: {
                        appState.exportSettings.format = $0
                        appState.markCustomSettings()
                    }
                ))
            }

            // Quality slider (only for JPEG/HEIC)
            if appState.exportSettings.format.supportsCompression && !appState.exportSettings.preserveOriginalFormat {
                QualitySlider(quality: Binding(
                    get: { appState.exportSettings.quality },
                    set: {
                        appState.exportSettings.quality = $0
                        appState.markCustomSettings()
                    }
                ))
            }

            // Rename settings
            RenameSettingsSection()

            // Preserve original format toggle
            Toggle("Keep original format", isOn: Binding(
                get: { appState.exportSettings.preserveOriginalFormat },
                set: {
                    appState.exportSettings.preserveOriginalFormat = $0
                    appState.markCustomSettings()
                }
            ))
            .font(.callout)

            Divider()

            // Resize settings
            ResizeSettingsSection()

            Divider()

            // Watermark settings
            WatermarkSettingsSection()

            // Output preview
            if let firstImage = appState.images.first {
                OutputPreview(inputURL: firstImage.url, exportSettings: appState.exportSettings)
            }

            // File size estimate
            if !appState.images.isEmpty && appState.cropSettings.hasAnyCrop {
                FileSizeEstimateView()
            }
        }
    }
}

// MARK: - Preset Picker

struct PresetPicker: View {
    @Environment(AppState.self) private var appState
    @State private var profileManager = ExportProfileManager.shared
    @State private var showSaveSheet = false
    @State private var newProfileName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Preset")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    newProfileName = "My Profile"
                    showSaveSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("Save current settings as profile")
            }

            Menu {
                // Built-in presets
                Section("Built-in") {
                    ForEach(ExportPreset.presets) { preset in
                        Button {
                            appState.applyPreset(preset)
                        } label: {
                            Label(preset.name, systemImage: preset.icon)
                        }
                    }
                }

                // User profiles (if any)
                if !profileManager.userProfiles.isEmpty {
                    Divider()

                    Section("My Profiles") {
                        ForEach(profileManager.userProfiles) { profile in
                            Button {
                                appState.exportSettings = profile.exportSettings
                                appState.selectedPresetID = nil
                            } label: {
                                Label(profile.name, systemImage: "person.crop.circle")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    if let preset = appState.selectedPreset {
                        Label(preset.name, systemImage: preset.icon)
                    } else {
                        Label("Custom", systemImage: "slider.horizontal.3")
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showSaveSheet) {
            SaveExportProfileSheet(profileName: $newProfileName) {
                showSaveSheet = false
            }
        }
    }
}

// MARK: - Save Export Profile Sheet

struct SaveExportProfileSheet: View {
    @Environment(AppState.self) private var appState
    @Binding var profileName: String
    let onDismiss: () -> Void
    @State private var profileManager = ExportProfileManager.shared

    var body: some View {
        VStack(spacing: 16) {
            Text("Save Export Profile")
                .font(.headline)

            TextField("Profile name", text: $profileName)
                .textFieldStyle(.roundedBorder)

            // Settings preview
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Format:")
                        .foregroundStyle(.secondary)
                    Text(appState.exportSettings.preserveOriginalFormat ? "Original" : appState.exportSettings.format.rawValue)
                }
                .font(.caption)

                if appState.exportSettings.format.supportsCompression && !appState.exportSettings.preserveOriginalFormat {
                    HStack {
                        Text("Quality:")
                            .foregroundStyle(.secondary)
                        Text("\(Int(appState.exportSettings.quality * 100))%")
                    }
                    .font(.caption)
                }

                HStack {
                    Text("Suffix:")
                        .foregroundStyle(.secondary)
                    Text(appState.exportSettings.suffix.isEmpty ? "(none)" : appState.exportSettings.suffix)
                        .fontDesign(.monospaced)
                }
                .font(.caption)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))

            HStack {
                Button("Cancel", role: .cancel) {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    profileManager.saveProfile(name: profileName, settings: appState.exportSettings)
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(profileName.isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
    }
}

// MARK: - Format Picker

struct FormatPicker: View {
    @Binding var format: ExportFormat

    var body: some View {
        HStack {
            Text("Format")
                .font(.callout)

            Spacer()

            Picker("", selection: $format) {
                ForEach(ExportFormat.allCases) { fmt in
                    Text(fmt.rawValue).tag(fmt)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 100)
        }
    }
}

// MARK: - Quality Slider

struct QualitySlider: View {
    @Binding var quality: Double

    private var qualityPercent: Int {
        Int(quality * 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Quality")
                    .font(.callout)
                Spacer()
                Text("\(qualityPercent)%")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Slider(value: $quality, in: 0.1...1.0, step: 0.05)
                .controlSize(.small)
        }
    }
}

// MARK: - Output Preview

struct OutputPreview: View {
    let inputURL: URL
    let exportSettings: ExportSettings

    private var outputFilename: String {
        exportSettings.outputURL(for: inputURL).lastPathComponent
    }

    private var wouldOverwrite: Bool {
        exportSettings.wouldOverwriteOriginal(for: inputURL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Output preview")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                if wouldOverwrite {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Text(outputFilename)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(wouldOverwrite ? .red : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if wouldOverwrite {
                Text("Would overwrite original!")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

// MARK: - Resize Settings Section

struct ResizeSettingsSection: View {
    @Environment(AppState.self) private var appState

    // Short labels for resize mode buttons
    private func shortLabel(for mode: ResizeMode) -> String {
        switch mode {
        case .none: return "None"
        case .exactSize: return "Exact"
        case .maxWidth: return "MaxW"
        case .maxHeight: return "MaxH"
        case .percentage: return "%"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Resize mode buttons
            VStack(spacing: 4) {
                Text("Resize")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    ForEach(ResizeMode.allCases) { mode in
                        Button {
                            appState.exportSettings.resizeSettings.mode = mode
                            appState.markCustomSettings()
                        } label: {
                            Text(shortLabel(for: mode))
                                .font(.system(size: 10, weight: .medium))
                                .frame(minWidth: 32, minHeight: 22)
                        }
                        .buttonStyle(.bordered)
                        .tint(appState.exportSettings.resizeSettings.mode == mode ? .accentColor : .secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            if appState.exportSettings.resizeSettings.mode != .none {
                resizeControls
            }
        }
    }

    @ViewBuilder
    private var resizeControls: some View {
        let mode = appState.exportSettings.resizeSettings.mode

        switch mode {
        case .none:
            EmptyView()

        case .exactSize:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Width")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Width", value: Binding(
                            get: { appState.exportSettings.resizeSettings.width },
                            set: {
                                appState.exportSettings.resizeSettings.width = max(1, $0)
                                appState.markCustomSettings()
                            }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    }

                    Text("×")
                        .foregroundStyle(.secondary)
                        .padding(.top, 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Height")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Height", value: Binding(
                            get: { appState.exportSettings.resizeSettings.height },
                            set: {
                                appState.exportSettings.resizeSettings.height = max(1, $0)
                                appState.markCustomSettings()
                            }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    }

                    Spacer()
                }

                Toggle("Maintain aspect ratio", isOn: Binding(
                    get: { appState.exportSettings.resizeSettings.maintainAspectRatio },
                    set: {
                        appState.exportSettings.resizeSettings.maintainAspectRatio = $0
                        appState.markCustomSettings()
                    }
                ))
                .font(.caption)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))

        case .maxWidth:
            HStack {
                Text("Max width")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                TextField("Width", value: Binding(
                    get: { appState.exportSettings.resizeSettings.width },
                    set: {
                        appState.exportSettings.resizeSettings.width = max(1, $0)
                        appState.markCustomSettings()
                    }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)

                Text("px")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .maxHeight:
            HStack {
                Text("Max height")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                TextField("Height", value: Binding(
                    get: { appState.exportSettings.resizeSettings.height },
                    set: {
                        appState.exportSettings.resizeSettings.height = max(1, $0)
                        appState.markCustomSettings()
                    }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)

                Text("px")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .percentage:
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Scale")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(appState.exportSettings.resizeSettings.percentage))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(value: Binding(
                    get: { appState.exportSettings.resizeSettings.percentage },
                    set: {
                        appState.exportSettings.resizeSettings.percentage = $0
                        appState.markCustomSettings()
                    }
                ), in: 10...200, step: 5)
                .controlSize(.small)
            }
        }
    }
}

// MARK: - Rename Settings Section

struct RenameSettingsSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Naming")
                    .font(.callout)

                Spacer()

                Picker("", selection: Binding(
                    get: { appState.exportSettings.renameSettings.mode },
                    set: {
                        appState.exportSettings.renameSettings.mode = $0
                        appState.markCustomSettings()
                    }
                )) {
                    ForEach(RenameMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }

            // Show suffix field for keep original mode, pattern field for pattern mode
            if appState.exportSettings.renameSettings.mode == .keepOriginal {
                HStack {
                    Text("Suffix")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    TextField("_cropped", text: Binding(
                        get: { appState.exportSettings.suffix },
                        set: {
                            appState.exportSettings.suffix = $0
                            appState.markCustomSettings()
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .multilineTextAlignment(.trailing)
                }
            } else {
                patternEditor
            }
        }
    }

    @ViewBuilder
    private var patternEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Pattern field
            HStack {
                Text("Pattern")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                TextField("{name}_{counter}", text: Binding(
                    get: { appState.exportSettings.renameSettings.pattern },
                    set: {
                        appState.exportSettings.renameSettings.pattern = $0
                        appState.markCustomSettings()
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)
                .font(.system(size: 11, design: .monospaced))
            }

            // Token buttons
            HStack(spacing: 4) {
                ForEach(RenameSettings.availableTokens, id: \.token) { token in
                    Button(token.token) {
                        appState.exportSettings.renameSettings.pattern += token.token
                        appState.markCustomSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help(token.description)
                }
            }

            // Counter settings
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("Start:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("1", value: Binding(
                        get: { appState.exportSettings.renameSettings.startIndex },
                        set: {
                            appState.exportSettings.renameSettings.startIndex = max(0, $0)
                            appState.markCustomSettings()
                        }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                }

                HStack(spacing: 4) {
                    Text("Digits:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("", selection: Binding(
                        get: { appState.exportSettings.renameSettings.zeroPadding },
                        set: {
                            appState.exportSettings.renameSettings.zeroPadding = $0
                            appState.markCustomSettings()
                        }
                    )) {
                        Text("1").tag(1)
                        Text("2").tag(2)
                        Text("3").tag(3)
                        Text("4").tag(4)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 55)
                }
            }

            // Preview
            if let firstImage = appState.images.first {
                let preview = appState.exportSettings.renameSettings.preview(
                    originalName: firstImage.url.deletingPathExtension().lastPathComponent,
                    index: 0
                )
                HStack(spacing: 4) {
                    Text("Preview:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(preview)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
    }
}


// MARK: - Draggable Number Field

struct DraggableNumberField: View {
    let label: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...9999
    var suffix: String? = nil
    var onCommit: (() -> Void)? = nil
    
    @State private var isDragging = false
    @State private var isHovering = false
    @State private var dragStartValue: Double = 0
    
    private let dragSensitivity: CGFloat = 2.0
    
    var body: some View {
        HStack(spacing: 4) {
            // Draggable label
            HStack(spacing: 2) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(isDragging ? .primary : .tertiary)
                
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isDragging ? .primary : (isHovering ? .primary : .secondary))
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(isDragging ? .primary : .tertiary)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isDragging ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isDragging ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else if !isDragging {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            dragStartValue = value
                        }
                        let delta = gesture.translation.width / dragSensitivity
                        let newValue = dragStartValue + delta
                        value = min(range.upperBound, max(range.lowerBound, newValue))
                    }
                    .onEnded { _ in
                        isDragging = false
                        if !isHovering {
                            NSCursor.pop()
                        }
                        onCommit?()
                    }
            )
            .help("Drag left/right to adjust value")
            
            TextField("", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 46)
                .font(.system(size: 11, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .onSubmit { onCommit?() }
            
            if let suffix = suffix {
                Text(suffix)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Watermark Settings Section

struct WatermarkSettingsSection: View {
    @Environment(AppState.self) private var appState
    @State private var showingFilePicker = false
    @State private var dragOver = false
    @State private var showVariablesPopover = false

    var body: some View {
        if appState.exportSettings.watermarkSettings.isEnabled {
            watermarkControls
        } else {
            Text("Enable to add text or image overlay")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var watermarkControls: some View {
        VStack(spacing: 12) {
            // Mode picker - proper segmented control
            Picker("", selection: Binding(
                get: { appState.exportSettings.watermarkSettings.mode },
                set: {
                    appState.exportSettings.watermarkSettings.mode = $0
                    appState.markCustomSettings()
                }
            )) {
                Label("Image", systemImage: "photo")
                    .tag(WatermarkMode.image)
                Label("Text", systemImage: "textformat")
                    .tag(WatermarkMode.text)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // Mode-specific content
            if appState.exportSettings.watermarkSettings.mode == .image {
                imagePickerSection
                if appState.exportSettings.watermarkSettings.isImageValid {
                    Divider()
                    sharedControls
                }
            } else {
                textWatermarkSection
                if appState.exportSettings.watermarkSettings.isTextValid {
                    Divider()
                    sharedControls
                }
            }
        }
    }

    @ViewBuilder
    private var sharedControls: some View {
        VStack(spacing: 12) {
            // Position
            positionPicker

            // Size (image only)
            if appState.exportSettings.watermarkSettings.mode == .image {
                sizeControls
            }

            // Opacity
            opacitySlider

            // Margin & Offset
            marginControl
        }
    }

    // MARK: - Text Watermark

    @ViewBuilder
    private var textWatermarkSection: some View {
        VStack(spacing: 12) {
            // Text input with variables button
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TextField("© {year}", text: Binding(
                        get: { appState.exportSettings.watermarkSettings.text },
                        set: {
                            appState.exportSettings.watermarkSettings.text = $0
                            appState.markCustomSettings()
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                    // Variables menu
                    Menu {
                        Section("File") {
                            variableMenuItem(.filename)
                            variableMenuItem(.index)
                            variableMenuItem(.count)
                        }
                        Section("Date") {
                            variableMenuItem(.date)
                            variableMenuItem(.year)
                            variableMenuItem(.month)
                            variableMenuItem(.day)
                        }
                    } label: {
                        Image(systemName: "textformat.subscript")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 24)
                    .help("Insert variable")
                }
            }

            // Font row - use LabeledContent pattern that works with Form
            LabeledContent {
                HStack(spacing: 8) {
                    // Font picker
                    Picker("", selection: Binding(
                        get: { appState.exportSettings.watermarkSettings.fontFamily },
                        set: {
                            appState.exportSettings.watermarkSettings.fontFamily = $0
                            appState.markCustomSettings()
                        }
                    )) {
                        ForEach(availableFontFamilies, id: \.self) { family in
                            Text(family).tag(family)
                        }
                    }
                    .labelsHidden()
                    
                    // Size with drag control
                    DraggableNumberField(
                        label: "Size",
                        value: Binding(
                            get: { appState.exportSettings.watermarkSettings.fontSize },
                            set: {
                                appState.exportSettings.watermarkSettings.fontSize = $0
                                appState.markCustomSettings()
                            }
                        ),
                        range: 8...500,
                        suffix: "pt"
                    )
                }
            } label: {
                EmptyView()
            }

            // Style row: Bold, Italic, Color
            HStack(spacing: 6) {
                // Bold/Italic group
                HStack(spacing: 0) {
                    Toggle(isOn: Binding(
                        get: { appState.exportSettings.watermarkSettings.isBold },
                        set: {
                            appState.exportSettings.watermarkSettings.isBold = $0
                            appState.markCustomSettings()
                        }
                    )) {
                        Image(systemName: "bold")
                            .frame(width: 24, height: 20)
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.borderless)

                    Divider()
                        .frame(height: 16)

                    Toggle(isOn: Binding(
                        get: { appState.exportSettings.watermarkSettings.isItalic },
                        set: {
                            appState.exportSettings.watermarkSettings.isItalic = $0
                            appState.markCustomSettings()
                        }
                    )) {
                        Image(systemName: "italic")
                            .frame(width: 24, height: 20)
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.borderless)
                }
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))

                Spacer()

                // Color
                HStack(spacing: 4) {
                    Text("Color")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ColorPicker("", selection: Binding(
                        get: { Color(nsColor: appState.exportSettings.watermarkSettings.textColor.nsColor) },
                        set: {
                            appState.exportSettings.watermarkSettings.textColor = CodableColor(NSColor($0))
                            appState.markCustomSettings()
                        }
                    ))
                    .labelsHidden()
                }
            }

            // Effects section
            effectsSection
        }
    }

    private func variableMenuItem(_ variable: TextWatermarkVariable) -> some View {
        Button {
            appState.exportSettings.watermarkSettings.text += variable.rawValue
            appState.markCustomSettings()
        } label: {
            Text(variable.rawValue)
            Text(variable.description)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var effectsSection: some View {
        VStack(spacing: 8) {
            // Shadow toggle with inline controls
            HStack {
                Toggle(isOn: Binding(
                    get: { appState.exportSettings.watermarkSettings.shadow.isEnabled },
                    set: {
                        appState.exportSettings.watermarkSettings.shadow.isEnabled = $0
                        appState.markCustomSettings()
                    }
                )) {
                    Text("Shadow")
                        .font(.callout)
                }

                Spacer()

                if appState.exportSettings.watermarkSettings.shadow.isEnabled {
                    ColorPicker("", selection: Binding(
                        get: { Color(nsColor: appState.exportSettings.watermarkSettings.shadow.color.nsColor) },
                        set: {
                            appState.exportSettings.watermarkSettings.shadow.color = CodableColor(NSColor($0))
                            appState.markCustomSettings()
                        }
                    ))
                    .labelsHidden()
                }
            }

            if appState.exportSettings.watermarkSettings.shadow.isEnabled {
                shadowControls
                    .padding(.leading, 20)
            }

            // Outline toggle with inline controls
            HStack {
                Toggle(isOn: Binding(
                    get: { appState.exportSettings.watermarkSettings.outline.isEnabled },
                    set: {
                        appState.exportSettings.watermarkSettings.outline.isEnabled = $0
                        appState.markCustomSettings()
                    }
                )) {
                    Text("Outline")
                        .font(.callout)
                }

                Spacer()

                if appState.exportSettings.watermarkSettings.outline.isEnabled {
                    ColorPicker("", selection: Binding(
                        get: { Color(nsColor: appState.exportSettings.watermarkSettings.outline.color.nsColor) },
                        set: {
                            appState.exportSettings.watermarkSettings.outline.color = CodableColor(NSColor($0))
                            appState.markCustomSettings()
                        }
                    ))
                    .labelsHidden()
                }
            }

            if appState.exportSettings.watermarkSettings.outline.isEnabled {
                outlineControls
                    .padding(.leading, 20)
            }
        }
    }

    @ViewBuilder
    private var shadowControls: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
            GridRow {
                Text("Blur")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .gridColumnAlignment(.trailing)
                Slider(value: Binding(
                    get: { appState.exportSettings.watermarkSettings.shadow.blur },
                    set: {
                        appState.exportSettings.watermarkSettings.shadow.blur = $0
                        appState.markCustomSettings()
                    }
                ), in: 0...20, step: 1)
                .controlSize(.small)
                Text("\(Int(appState.exportSettings.watermarkSettings.shadow.blur))")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 24)
            }
            GridRow {
                Text("Offset")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    HStack(spacing: 2) {
                        Text("X")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        TextField("", value: Binding(
                            get: { appState.exportSettings.watermarkSettings.shadow.offsetX },
                            set: {
                                appState.exportSettings.watermarkSettings.shadow.offsetX = $0
                                appState.markCustomSettings()
                            }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 36)
                    }
                    HStack(spacing: 2) {
                        Text("Y")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        TextField("", value: Binding(
                            get: { appState.exportSettings.watermarkSettings.shadow.offsetY },
                            set: {
                                appState.exportSettings.watermarkSettings.shadow.offsetY = $0
                                appState.markCustomSettings()
                            }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 36)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var outlineControls: some View {
        HStack {
            Text("Width")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: Binding(
                get: { appState.exportSettings.watermarkSettings.outline.width },
                set: {
                    appState.exportSettings.watermarkSettings.outline.width = $0
                    appState.markCustomSettings()
                }
            ), in: 0.5...10, step: 0.5)
            .controlSize(.small)
            Text("\(appState.exportSettings.watermarkSettings.outline.width, specifier: "%.1f")")
                .font(.caption)
                .monospacedDigit()
                .frame(width: 28)
        }
    }

    private var availableFontFamilies: [String] {
        NSFontManager.shared.availableFontFamilies.sorted()
    }

    @ViewBuilder
    private var imagePickerSection: some View {
        VStack(spacing: 6) {
            if let imageURL = appState.exportSettings.watermarkSettings.imageURL,
               let image = appState.exportSettings.watermarkSettings.cachedImage {
                // Show preview with remove button (use cached image, not URL - sandbox!)
                HStack {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 40)
                        .background(
                            // Checkerboard pattern for transparency
                            Image(systemName: "checkerboard.rectangle")
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .foregroundStyle(.quaternary)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(imageURL.lastPathComponent)
                            .font(.caption)
                            .lineLimit(1)
                        Text("\(Int(image.size.width)) × \(Int(image.size.height))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        clearWatermark()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                // Drop zone for image
                VStack(spacing: 4) {
                    Image(systemName: "photo.badge.plus")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Drop PNG or click to choose")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                        .foregroundStyle(dragOver ? .blue : .secondary.opacity(0.5))
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    showingFilePicker = true
                }
                .onDrop(of: [.fileURL], isTargeted: $dragOver) { providers in
                    handleDrop(providers)
                }
                .fileImporter(
                    isPresented: $showingFilePicker,
                    allowedContentTypes: [.png, .jpeg, .heic, .webP, .tiff],
                    allowsMultipleSelection: false
                ) { result in
                    handleFileSelection(result)
                }
            }
        }
    }

    @ViewBuilder
    private var positionPicker: some View {
        HStack(spacing: 12) {
            Text("Position")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            // Compact 3x3 position grid
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow {
                    positionDot(.topLeft)
                    positionDot(.topCenter)
                    positionDot(.topRight)
                }
                GridRow {
                    positionDot(.centerLeft)
                    positionDot(.center)
                    positionDot(.centerRight)
                }
                GridRow {
                    positionDot(.bottomLeft)
                    positionDot(.bottomCenter)
                    positionDot(.bottomRight)
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }

    private func positionDot(_ position: WatermarkPosition) -> some View {
        let isSelected = appState.exportSettings.watermarkSettings.position == position
        return Button {
            appState.exportSettings.watermarkSettings.position = position
            appState.markCustomSettings()
        } label: {
            Circle()
                .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.3))
                .frame(width: 12, height: 12)
        }
        .buttonStyle(.plain)
        .help(position.rawValue)
    }

    @ViewBuilder
    private var sizeControls: some View {
        VStack(spacing: 8) {
            // Size mode picker
            Picker("Size", selection: Binding(
                get: { appState.exportSettings.watermarkSettings.sizeMode },
                set: {
                    appState.exportSettings.watermarkSettings.sizeMode = $0
                    appState.markCustomSettings()
                }
            )) {
                Text("Original").tag(WatermarkSizeMode.original)
                Text("Scale %").tag(WatermarkSizeMode.percentage)
                Text("Width").tag(WatermarkSizeMode.fixedWidth)
                Text("Height").tag(WatermarkSizeMode.fixedHeight)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if appState.exportSettings.watermarkSettings.sizeMode != .original {
                HStack {
                    Slider(value: Binding(
                        get: { appState.exportSettings.watermarkSettings.sizeValue },
                        set: {
                            appState.exportSettings.watermarkSettings.sizeValue = $0
                            appState.markCustomSettings()
                        }
                    ), in: sizeRange, step: sizeStep)
                    .controlSize(.small)

                    Text(sizeLabel)
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }
            }
        }
    }

    private var sizeRange: ClosedRange<Double> {
        switch appState.exportSettings.watermarkSettings.sizeMode {
        case .original: return 0...100
        case .percentage: return 5...50
        case .fixedWidth, .fixedHeight: return 50...500
        }
    }

    private var sizeStep: Double {
        switch appState.exportSettings.watermarkSettings.sizeMode {
        case .original: return 1
        case .percentage: return 1
        case .fixedWidth, .fixedHeight: return 10
        }
    }

    private var sizeLabel: String {
        let value = appState.exportSettings.watermarkSettings.sizeValue
        switch appState.exportSettings.watermarkSettings.sizeMode {
        case .original: return ""
        case .percentage: return "\(Int(value))%"
        case .fixedWidth, .fixedHeight: return "\(Int(value))px"
        }
    }

    @ViewBuilder
    private var opacitySlider: some View {
        HStack {
            Text("Opacity")
                .font(.callout)
                .foregroundStyle(.secondary)

            Slider(value: Binding(
                get: { appState.exportSettings.watermarkSettings.opacity },
                set: {
                    appState.exportSettings.watermarkSettings.opacity = $0
                    appState.markCustomSettings()
                }
            ), in: 0.1...1.0, step: 0.05)
            .controlSize(.small)

            Text("\(Int(appState.exportSettings.watermarkSettings.opacity * 100))%")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    private var marginControl: some View {
        VStack(spacing: 8) {
            // Margin from edge - use LabeledContent like CropControlsView
            LabeledContent("Margin") {
                DraggableNumberField(
                    label: "M",
                    value: Binding(
                        get: { appState.exportSettings.watermarkSettings.margin },
                        set: {
                            appState.exportSettings.watermarkSettings.margin = $0
                            appState.markCustomSettings()
                        }
                    ),
                    range: 0...500,
                    suffix: "px"
                )
            }

            // Fine-tune offset (pixels) - use LabeledContent like CropControlsView
            LabeledContent("Offset") {
                HStack(spacing: 4) {
                    DraggableNumberField(
                        label: "X",
                        value: Binding(
                            get: { appState.exportSettings.watermarkSettings.offsetX },
                            set: {
                                appState.exportSettings.watermarkSettings.offsetX = $0
                                appState.markCustomSettings()
                            }
                        ),
                        range: -2000...2000
                    )
                    
                    DraggableNumberField(
                        label: "Y",
                        value: Binding(
                            get: { appState.exportSettings.watermarkSettings.offsetY },
                            set: {
                                appState.exportSettings.watermarkSettings.offsetY = $0
                                appState.markCustomSettings()
                            }
                        ),
                        range: -2000...2000
                    )

                    // Reset button
                    if appState.exportSettings.watermarkSettings.offsetX != 0 ||
                       appState.exportSettings.watermarkSettings.offsetY != 0 {
                        Button {
                            appState.exportSettings.watermarkSettings.offsetX = 0
                            appState.exportSettings.watermarkSettings.offsetY = 0
                            appState.markCustomSettings()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Reset offset to 0")
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
            guard let data = data as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

            DispatchQueue.main.async {
                loadWatermarkImage(from: url)
            }
        }
        return true
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        if case .success(let urls) = result, let url = urls.first {
            loadWatermarkImage(from: url, isSecurityScoped: true)
        }
    }

    private func loadWatermarkImage(from url: URL, isSecurityScoped: Bool = false) {
        // For sandboxed apps, fileImporter URLs require security-scoped access
        let didStartAccess = isSecurityScoped && url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // Load and store the image DATA (not just cache) - survives state changes
        guard let imageData = try? Data(contentsOf: url),
              let image = NSImage(data: imageData) else {
            print("Failed to load watermark image from: \(url.path)")
            return
        }

        appState.exportSettings.watermarkSettings.imageURL = url
        appState.exportSettings.watermarkSettings.imageData = imageData  // Store the data!
        appState.exportSettings.watermarkSettings.cachedImage = image
        appState.exportSettings.watermarkSettings.isEnabled = true
        appState.markCustomSettings()
    }

    private func clearWatermark() {
        appState.exportSettings.watermarkSettings.imageURL = nil
        appState.exportSettings.watermarkSettings.imageData = nil
        appState.exportSettings.watermarkSettings.cachedImage = nil
        appState.markCustomSettings()
    }
}

// MARK: - File Size Estimate

struct FileSizeEstimateView: View {
    @Environment(AppState.self) private var appState

    private var estimate: FileSizeEstimate {
        FileSizeEstimator.estimate(
            images: appState.images,
            cropSettings: appState.cropSettings,
            exportSettings: appState.exportSettings
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            // Percentage badge
            Text("\(Int(estimate.percentage))%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(percentageColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(percentageColor.opacity(0.15)))

            // Size: estimated from original
            Text("\(estimate.estimatedTotal.formattedFileSize) from \(estimate.originalTotal.formattedFileSize)")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer()

            // Savings indicator
            if estimate.savings > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text("−\(estimate.savings.formattedFileSize)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.green)
                }
            } else if estimate.savings < 0 {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text("+\((-estimate.savings).formattedFileSize)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private var percentageColor: Color {
        if estimate.percentage < 50 {
            return .green
        } else if estimate.percentage < 100 {
            return .blue
        } else {
            return .orange
        }
    }
}

#Preview {
    ExportSettingsView()
        .environment(AppState())
        .frame(width: 250)
        .padding()
}
