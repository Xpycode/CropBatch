import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        HStack(spacing: 0) {
            // Main content area (left)
            if appState.images.isEmpty {
                DropZoneView()
            } else {
                VStack(spacing: 0) {
                    // Main crop editor
                    if let activeImage = appState.activeImage {
                        CropEditorView(image: activeImage)
                    }

                    // Thumbnail strip at bottom
                    ThumbnailStripView()
                }
            }

            Divider()

            // Sidebar (right)
            SidebarView()
                .frame(width: 420)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
        .toolbar {
            // Center: Zoom controls only
            ToolbarItem(placement: .principal) {
                if !appState.images.isEmpty {
                    ZoomPicker(selection: Binding(
                        get: { appState.zoomMode },
                        set: { appState.zoomMode = $0 }
                    ))
                }
            }

            // Right side: buttons only
            ToolbarItemGroup(placement: .primaryAction) {
                if !appState.images.isEmpty {
                    Button {
                        appState.showImportPanel()
                    } label: {
                        Label("Add Images", systemImage: "plus")
                    }

                    Button(role: .destructive) {
                        appState.clearAll()
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                }
            }
        }
    }

    private func zoomInfoText(for image: ImageItem) -> String {
        let scale = calculateZoomScale(for: image)
        let percentage = Int(scale * 100)
        return "\(percentage)%  \(Int(image.originalSize.width))×\(Int(image.originalSize.height))"
    }

    private func calculateZoomScale(for image: ImageItem) -> CGFloat {
        // Approximate scale based on typical view size
        // This is a simplified calculation for display purposes
        let availableWidth: CGFloat = 500
        let availableHeight: CGFloat = 400

        switch appState.zoomMode {
        case .actualSize:
            return 1.0
        case .fit:
            let scaleX = availableWidth / image.originalSize.width
            let scaleY = availableHeight / image.originalSize.height
            return min(scaleX, scaleY, 1.0)
        case .fitWidth:
            return availableWidth / image.originalSize.width
        case .fitHeight:
            return availableHeight / image.originalSize.height
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false

        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        DispatchQueue.main.async {
                            appState.addImages(from: [url])
                        }
                    }
                }
                handled = true
            }
        }

        return handled
    }
}

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    // Collapsed state persistence
    @AppStorage("sidebar.snapExpanded") private var snapExpanded = false
    @AppStorage("sidebar.qualityResizeExpanded") private var qualityResizeExpanded = false
    @AppStorage("sidebar.watermarkExpanded") private var watermarkExpanded = false
    @AppStorage("sidebar.shortcutsExpanded") private var shortcutsExpanded = false

    var body: some View {
        @Bindable var state = appState
        
        VStack(spacing: 0) {
            // Scrollable content using Form for inspector-style layout
            Form {
                // Resolution warning (always visible if needed)
                if appState.hasResolutionMismatch {
                    Section {
                        ResolutionWarningView()
                    }
                }

                // ═══════════════════════════════════════
                // CROP - Primary controls, always visible
                // ═══════════════════════════════════════
                Section {
                    CropControlsView()
                }

                // ═══════════════════════════════════════
                // ASPECT GUIDE - Always visible (quick access)
                // ═══════════════════════════════════════
                Section {
                    AspectGuideView()
                }

                // ═══════════════════════════════════════
                // SNAP - Toggle in header, options when expanded
                // ═══════════════════════════════════════
                Section(isExpanded: $snapExpanded) {
                    SnapOptionsView()
                } header: {
                    HStack {
                        Text("Snap to Edges")
                        Spacer()
                        Toggle("", isOn: $state.snapEnabled)
                            .labelsHidden()
                            .controlSize(.small)
                            .onChange(of: appState.snapEnabled) { _, isEnabled in
                                if isEnabled {
                                    withAnimation { snapExpanded = true }
                                }
                            }
                    }
                }

                // ═══════════════════════════════════════
                // EXPORT FORMAT - Always visible
                // ═══════════════════════════════════════
                Section {
                    ExportFormatView()
                }

                // ═══════════════════════════════════════
                // QUALITY & RESIZE - Collapsed by default
                // ═══════════════════════════════════════
                Section("Quality & Resize", isExpanded: $qualityResizeExpanded) {
                    QualityResizeView()
                }

                // ═══════════════════════════════════════
                // WATERMARK - Toggle in header
                // ═══════════════════════════════════════
                Section(isExpanded: $watermarkExpanded) {
                    WatermarkSettingsSection()
                } header: {
                    HStack {
                        Text("Watermark")
                        Spacer()
                        Toggle("", isOn: $state.exportSettings.watermarkSettings.isEnabled)
                            .labelsHidden()
                            .controlSize(.small)
                            .onChange(of: appState.exportSettings.watermarkSettings.isEnabled) { _, isEnabled in
                                if isEnabled {
                                    withAnimation { watermarkExpanded = true }
                                }
                            }
                    }
                }

                // ═══════════════════════════════════════
                // KEYBOARD SHORTCUTS - Collapsed
                // ═══════════════════════════════════════
                Section("Keyboard Shortcuts", isExpanded: $shortcutsExpanded) {
                    KeyboardShortcutsContentView()
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(alignment: .trailing) {
                // Fill the scrollbar gutter gap
                Color(nsColor: .controlBackgroundColor)
                    .frame(width: 14)
                    .ignoresSafeArea()
            }

            // ═══════════════════════════════════════
            // STICKY FOOTER - File size + Export button
            // ═══════════════════════════════════════
            ExportFooterView()
        }
    }
}

// MARK: - Crop Section (Primary)

struct CropSectionView: View {
    @Environment(AppState.self) private var appState
    @State private var presetManager = PresetManager.shared

    var body: some View {
        @Bindable var state = appState

        VStack(alignment: .leading, spacing: 12) {
            // Tool selector (centered)
            // TODO: [SHELVED] Blur tool - transform coordinate mismatch when images are rotated/flipped
            // See docs/blur-feature-status.md for details. Remove filter to re-enable.
            HStack(spacing: 0) {
                ForEach(EditorTool.allCases.filter { $0 != .blur }) { tool in  // SHELVED: Blur tool
                    Button {
                        appState.currentTool = tool
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: tool.icon)
                            Text(tool.rawValue)
                        }
                        .font(.system(size: 12, weight: appState.currentTool == tool ? .semibold : .regular))
                        .foregroundStyle(appState.currentTool == tool ? .primary : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            appState.currentTool == tool
                                ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.15))
                                : nil
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)

            // Tool-specific controls
            if appState.currentTool == .crop {
                // MARK: Crop Tool Controls

                // TODO: [SHELVED] Preset picker - simplified UI for now
                #if false
                HStack {
                    Menu {
                        Button {
                            appState.cropSettings = CropSettings()
                            appState.recordCropChange()
                        } label: {
                            Label("None (Reset)", systemImage: "xmark")
                        }

                        Divider()

                        // Group by category
                        ForEach(PresetCategory.allCases) { category in
                            let categoryPresets = presetManager.allPresets.filter { $0.category == category }
                            if !categoryPresets.isEmpty {
                                Menu {
                                    ForEach(categoryPresets) { preset in
                                        Button {
                                            appState.applyCropPreset(preset)
                                        } label: {
                                            Text("\(preset.name) \(presetValues(preset))")
                                        }
                                    }
                                } label: {
                                    Label(category.rawValue, systemImage: category.icon)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "square.stack")
                                .foregroundStyle(.secondary)
                            Text("Preset")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                    }
                    .buttonStyle(.plain)

                    // Link mode button - shelved (not working reliably)
                }
                #endif

                // Crop edge inputs - centered
                HStack(spacing: 8) {
                    CompactCropField(label: "T", value: $state.cropSettings.cropTop) {
                        appState.recordCropChange()
                    }
                    CompactCropField(label: "B", value: $state.cropSettings.cropBottom) {
                        appState.recordCropChange()
                    }
                    CompactCropField(label: "L", value: $state.cropSettings.cropLeft) {
                        appState.recordCropChange()
                    }
                    CompactCropField(label: "R", value: $state.cropSettings.cropRight) {
                        appState.recordCropChange()
                    }
                }
                .frame(maxWidth: .infinity)

                // Reset button - centered below
                Button {
                    appState.cropSettings = CropSettings()
                    appState.recordCropChange()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset Crop")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(!appState.cropSettings.hasAnyCrop)
                .help("Reset crop")
                .frame(maxWidth: .infinity)

                // Corner Radius section
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: $state.cropSettings.cornerRadiusEnabled) {
                        Text("Corner Radius")
                            .font(.caption)
                    }
                    .toggleStyle(.checkbox)
                    .controlSize(.small)

                    if appState.cropSettings.cornerRadiusEnabled {
                        HStack(spacing: 6) {
                            TextField("10", value: $state.cropSettings.cornerRadius, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 50)
                                .multilineTextAlignment(.trailing)
                                .controlSize(.small)

                            Text("px")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Toggle(isOn: $state.cropSettings.independentCorners) {
                                Text("Per-corner")
                                    .font(.caption2)
                            }
                            .toggleStyle(.checkbox)
                            .controlSize(.mini)
                        }

                        if appState.cropSettings.independentCorners {
                            HStack(spacing: 4) {
                                VStack(spacing: 2) {
                                    HStack(spacing: 2) {
                                        Text("TL")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                        TextField("", value: $state.cropSettings.cornerRadiusTL, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 36)
                                            .controlSize(.mini)
                                    }
                                    HStack(spacing: 2) {
                                        Text("BL")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                        TextField("", value: $state.cropSettings.cornerRadiusBL, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 36)
                                            .controlSize(.mini)
                                    }
                                }
                                Spacer()
                                VStack(spacing: 2) {
                                    HStack(spacing: 2) {
                                        TextField("", value: $state.cropSettings.cornerRadiusTR, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 36)
                                            .controlSize(.mini)
                                        Text("TR")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                    }
                                    HStack(spacing: 2) {
                                        TextField("", value: $state.cropSettings.cornerRadiusBR, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 36)
                                            .controlSize(.mini)
                                        Text("BR")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        Text("PNG output (transparency)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

                Divider()

                // Snap to edges toggle
                HStack(spacing: 6) {
                    Toggle(isOn: $state.snapEnabled) {
                        Label("Snap to Edges", systemImage: "magnet")
                            .font(.caption)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                    if appState.isDetectingSnapPoints {
                        ProgressView()
                            .controlSize(.mini)
                    } else if appState.snapEnabled && appState.activeSnapPoints.hasDetections {
                        Text("\(appState.activeSnapPoints.horizontalEdges.count + appState.activeSnapPoints.verticalEdges.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.2)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)

                // Snap options (only show when snap is enabled)
                if appState.snapEnabled {
                    VStack(spacing: 6) {
                        // Threshold slider
                        HStack(spacing: 4) {
                            Text("Threshold")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Slider(value: Binding(
                                get: { Double(appState.snapThreshold) },
                                set: { appState.snapThreshold = Int($0) }
                            ), in: 5...30, step: 1)
                            .controlSize(.mini)
                            Text("\(appState.snapThreshold)px")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 30)
                        }

                        // Option toggles in a compact grid
                        HStack(spacing: 12) {
                            Toggle(isOn: $state.snapToCenter) {
                                Text("Center")
                                    .font(.caption2)
                            }
                            .toggleStyle(.checkbox)
                            .controlSize(.mini)
                            .help("Also snap to image center lines")

                            Toggle(isOn: $state.showSnapDebug) {
                                Text("Debug")
                                    .font(.caption2)
                            }
                            .toggleStyle(.checkbox)
                            .controlSize(.mini)
                            .help("Show all detected edges")
                        }
                        Text("Hold ⌥ to bypass snap")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 2)
                }

                // Aspect guide options (always visible)
                Divider()
                AdvancedCropOptionsView()

            } else if appState.currentTool == .blur {
                // MARK: Blur Tool Controls
                BlurToolSettingsPanel()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func presetValues(_ preset: CropPreset) -> String {
        let s = preset.cropSettings
        var parts: [String] = []
        if s.cropTop > 0 { parts.append("T:\(s.cropTop)") }
        if s.cropBottom > 0 { parts.append("B:\(s.cropBottom)") }
        if s.cropLeft > 0 { parts.append("L:\(s.cropLeft)") }
        if s.cropRight > 0 { parts.append("R:\(s.cropRight)") }
        return parts.isEmpty ? "" : "(\(parts.joined(separator: ", ")))"
    }
}

// MARK: - Compact Crop Field

struct CompactCropField: View {
    let label: String
    @Binding var value: Int
    var onCommit: (() -> Void)?
    
    @State private var isDragging = false
    @State private var isHovering = false
    @State private var dragStartValue: Int = 0
    
    // Sensitivity: points of drag per 1px value change
    private let dragSensitivity: CGFloat = 2.0

    var body: some View {
        HStack(spacing: 4) {
            // Draggable label with always-visible styling
            HStack(spacing: 2) {
                // Drag indicator chevrons
                Image(systemName: "chevron.left")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(isDragging ? .primary : .tertiary)
                
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isDragging ? .primary : (isHovering ? .primary : .secondary))
                    .lineLimit(1)
                    .fixedSize()
                
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
                        let delta = Int(gesture.translation.width / dragSensitivity)
                        value = max(0, dragStartValue + delta)
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
        }
    }
}

// MARK: - Advanced Crop Options

struct AdvancedCropOptionsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Aspect ratio guide
            VStack(alignment: .leading, spacing: 4) {
                Text("Aspect Guide")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Button {
                        appState.showAspectRatioGuide = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .frame(width: 28, height: 22)
                    }
                    .buttonStyle(.bordered)
                    .tint(appState.showAspectRatioGuide == nil ? .accentColor : .secondary)

                    ForEach(AspectRatioGuide.allCases) { guide in
                        Button {
                            appState.showAspectRatioGuide = guide
                        } label: {
                            Text(guide.rawValue)
                                .font(.system(size: 9, weight: .medium))
                                .frame(minWidth: 28, minHeight: 22)
                        }
                        .buttonStyle(.bordered)
                        .tint(appState.showAspectRatioGuide == guide ? .yellow : .secondary)
                    }
                }
            }

            // Auto-detect - shelved (not working reliably)
        }
    }
}


// MARK: - Crop Controls (Always Visible)

struct CropControlsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        // Crop edge inputs - horizontal row
        LabeledContent("Crop") {
            HStack(spacing: 6) {
                CompactCropField(label: "T", value: $state.cropSettings.cropTop) {
                    appState.recordCropChange()
                }
                CompactCropField(label: "B", value: $state.cropSettings.cropBottom) {
                    appState.recordCropChange()
                }
                CompactCropField(label: "L", value: $state.cropSettings.cropLeft) {
                    appState.recordCropChange()
                }
                CompactCropField(label: "R", value: $state.cropSettings.cropRight) {
                    appState.recordCropChange()
                }
            }
        }
        .controlSize(.small)

        // Reset button
        Button {
            appState.cropSettings = CropSettings()
            appState.recordCropChange()
        } label: {
            Label("Reset Crop", systemImage: "arrow.counterclockwise")
        }
        .controlSize(.small)
        .disabled(!appState.cropSettings.hasAnyCrop)
        .help("Reset crop to zero")

        // Corner Radius
        LabeledContent("Corner Radius") {
            Toggle("", isOn: $state.cropSettings.cornerRadiusEnabled)
                .labelsHidden()
                .controlSize(.small)
        }

        if appState.cropSettings.cornerRadiusEnabled {
            // Radius controls - same structure as crop section
            LabeledContent {
                HStack(spacing: 6) {
                    if appState.cropSettings.independentCorners {
                        CompactCropField(label: "TL", value: $state.cropSettings.cornerRadiusTL)
                        CompactCropField(label: "TR", value: $state.cropSettings.cornerRadiusTR)
                        CompactCropField(label: "BL", value: $state.cropSettings.cornerRadiusBL)
                        CompactCropField(label: "BR", value: $state.cropSettings.cornerRadiusBR)
                    } else {
                        CompactCropField(label: "R", value: $state.cropSettings.cornerRadius)
                    }
                }
            } label: {
                Toggle("Per-corner", isOn: $state.cropSettings.independentCorners)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
            }

            Text("Exports as PNG for transparency")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Snap Options (Content only, toggle in header)

struct SnapOptionsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        LabeledContent("Threshold") {
            HStack(spacing: 8) {
                Slider(value: Binding(
                    get: { Double(appState.snapThreshold) },
                    set: { appState.snapThreshold = Int($0) }
                ), in: 5...30, step: 1)
                .frame(maxWidth: 100)
                Text("\(appState.snapThreshold)px")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
            }
        }

        Toggle("Snap to Center", isOn: $state.snapToCenter)
            .help("Also snap to image center lines")

        Toggle("Show Debug", isOn: $state.showSnapDebug)
            .help("Show all detected edges")

        Text("Hold ⌥ to bypass snap")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }
}

// MARK: - Aspect Guide (Always Visible)

struct AspectGuideView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        LabeledContent("Aspect") {
            HStack(spacing: 3) {
                Button {
                    appState.showAspectRatioGuide = nil
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 24)
                }
                .buttonStyle(.bordered)
                .tint(appState.showAspectRatioGuide == nil ? .accentColor : .secondary)

                ForEach(AspectRatioGuide.allCases) { guide in
                    Button {
                        appState.showAspectRatioGuide = guide
                    } label: {
                        Text(guide.rawValue)
                            .frame(minWidth: 24)
                    }
                    .buttonStyle(.bordered)
                    .tint(appState.showAspectRatioGuide == guide ? .yellow : .secondary)
                }
            }
            .controlSize(.small)
        }
    }
}

// MARK: - Export Format (Always Visible)

struct ExportFormatView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        // Format selection
        LabeledContent("Format") {
            HStack(spacing: 4) {
                ForEach(ExportFormat.allCases) { fmt in
                    Button {
                        appState.exportSettings.format = fmt
                        appState.markCustomSettings()
                    } label: {
                        Text(fmt.rawValue)
                            .frame(minWidth: 32)
                    }
                    .buttonStyle(.bordered)
                    .tint(appState.exportSettings.format == fmt ? .accentColor : .secondary)
                }
            }
            .controlSize(.small)
        }

        // Naming selection
        LabeledContent("Naming") {
            Picker("", selection: Binding(
                get: { appState.exportSettings.renameSettings.mode },
                set: { appState.exportSettings.renameSettings.mode = $0; appState.markCustomSettings() }
            )) {
                ForEach(RenameMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
        }

        // Output preview
        if let firstImage = appState.images.first {
            LabeledContent("Output") {
                Text(appState.exportSettings.outputFilename(for: firstImage.url))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

// MARK: - Quality & Resize (Collapsible)

struct QualityResizeView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        // Quality slider (for JPEG/HEIC/WebP)
        if appState.exportSettings.format.supportsCompression {
            LabeledContent("Quality") {
                HStack(spacing: 8) {
                    Slider(value: Binding(
                        get: { appState.exportSettings.quality },
                        set: { appState.exportSettings.quality = $0; appState.markCustomSettings() }
                    ), in: 0.1...1.0, step: 0.05)
                    .frame(maxWidth: 120)
                    Text("\(Int(appState.exportSettings.quality * 100))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }

        // Suffix field (when using Keep Original naming)
        if appState.exportSettings.renameSettings.mode == .keepOriginal {
            LabeledContent("Suffix") {
                TextField("", text: Binding(
                    get: { appState.exportSettings.suffix },
                    set: { appState.exportSettings.suffix = $0; appState.markCustomSettings() }
                ), prompt: Text("_cropped"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
            }
        }

        // Pattern field (when using Pattern naming)
        if appState.exportSettings.renameSettings.mode == .pattern {
            LabeledContent("Pattern") {
                TextField("", text: Binding(
                    get: { appState.exportSettings.renameSettings.pattern },
                    set: { appState.exportSettings.renameSettings.pattern = $0; appState.markCustomSettings() }
                ), prompt: Text("{name}_{n}"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
                .font(.system(.body, design: .monospaced))
            }

            // Token buttons
            LabeledContent("Tokens") {
                HStack(spacing: 4) {
                    ForEach(RenameSettings.availableTokens, id: \.token) { token in
                        Button(token.token) {
                            appState.exportSettings.renameSettings.pattern += token.token
                            appState.markCustomSettings()
                        }
                        .help(token.description)
                    }
                }
                .controlSize(.mini)
                .buttonStyle(.bordered)
            }
        }

        // Resize settings - use LabeledContent for consistency
        LabeledContent("Resize") {
            HStack(spacing: 4) {
                ForEach(ResizeMode.allCases) { mode in
                    Button {
                        appState.exportSettings.resizeSettings.mode = mode
                        appState.markCustomSettings()
                    } label: {
                        Text(shortLabel(for: mode))
                            .frame(minWidth: 28)
                    }
                    .buttonStyle(.bordered)
                    .tint(appState.exportSettings.resizeSettings.mode == mode ? .accentColor : .secondary)
                }
            }
            .controlSize(.small)
        }

        // Resize dimension controls when not "none"
        if appState.exportSettings.resizeSettings.mode != .none {
            resizeControls
        }
    }

    private func shortLabel(for mode: ResizeMode) -> String {
        switch mode {
        case .none: return "None"
        case .exactSize: return "Exact"
        case .maxWidth: return "W"
        case .maxHeight: return "H"
        case .percentage: return "%"
        }
    }

    @ViewBuilder
    private var resizeControls: some View {
        switch appState.exportSettings.resizeSettings.mode {
        case .none:
            EmptyView()
        case .exactSize:
            LabeledContent("Size") {
                HStack(spacing: 4) {
                    TextField("W", value: Binding(
                        get: { appState.exportSettings.resizeSettings.width },
                        set: { appState.exportSettings.resizeSettings.width = $0; appState.markCustomSettings() }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    Text("×")
                        .foregroundStyle(.secondary)
                    TextField("H", value: Binding(
                        get: { appState.exportSettings.resizeSettings.height },
                        set: { appState.exportSettings.resizeSettings.height = $0; appState.markCustomSettings() }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                }
            }
        case .maxWidth:
            LabeledContent("Max Width") {
                TextField("px", value: Binding(
                    get: { appState.exportSettings.resizeSettings.width },
                    set: { appState.exportSettings.resizeSettings.width = $0; appState.markCustomSettings() }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
            }
        case .maxHeight:
            LabeledContent("Max Height") {
                TextField("px", value: Binding(
                    get: { appState.exportSettings.resizeSettings.height },
                    set: { appState.exportSettings.resizeSettings.height = $0; appState.markCustomSettings() }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
            }
        case .percentage:
            LabeledContent("Scale") {
                HStack(spacing: 4) {
                    Slider(value: Binding(
                        get: { appState.exportSettings.resizeSettings.percentage },
                        set: { appState.exportSettings.resizeSettings.percentage = $0; appState.markCustomSettings() }
                    ), in: 10...200, step: 5)
                    .frame(width: 100)
                    Text("\(Int(appState.exportSettings.resizeSettings.percentage))%")
                        .monospacedDigit()
                        .frame(width: 40)
                }
            }
        }
    }
}

// MARK: - Export Footer (Sticky)

struct ExportFooterView: View {
    @Environment(AppState.self) private var appState
    @State private var coordinator = ExportCoordinator()

    private var imagesToProcess: [ImageItem] {
        if appState.selectedImageIDs.isEmpty {
            return appState.images
        } else {
            return appState.images.filter { appState.selectedImageIDs.contains($0.id) }
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Divider()

            // File size estimate
            if !appState.images.isEmpty {
                FileSizeEstimateView()
            }

            // Warning if nothing to export
            if !appState.canExport && !appState.images.isEmpty && !appState.isProcessing {
                Label("Apply crop, transform, or resize to export", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            // Export button - prominent action
            Button {
                coordinator.selectOutputFolder()
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.down.fill")
                    Text(appState.selectedImageIDs.isEmpty
                         ? "Export All (\(appState.images.count))"
                         : "Export Selected (\(appState.selectedImageIDs.count))")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!appState.canExport)

            // Progress indicator
            if appState.isProcessing {
                ProgressView(value: appState.processingProgress) {
                    Text("Exporting \(Int(appState.processingProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .progressViewStyle(.linear)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .onAppear { coordinator.setAppState(appState) }
        .exportSheets(coordinator: coordinator, appState: appState, imagesToProcess: imagesToProcess)
    }
}

// MARK: - Transform Row

struct TransformRowView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 8) {
            Label("Transform", systemImage: "rotate.right")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // Rotate buttons
            Button {
                appState.rotateActiveImage(clockwise: false)
            } label: {
                Image(systemName: "rotate.left")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(appState.activeImage == nil)
            .help("Rotate Left (⌘[)")

            Button {
                appState.rotateActiveImage(clockwise: true)
            } label: {
                Image(systemName: "rotate.right")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(appState.activeImage == nil)
            .help("Rotate Right (⌘])")

            Divider()
                .frame(height: 20)

            // Flip buttons
            Button {
                appState.flipActiveImage(horizontal: true)
            } label: {
                Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(appState.activeImage == nil)
            .help("Flip Horizontal")

            Button {
                appState.flipActiveImage(horizontal: false)
            } label: {
                Image(systemName: "arrow.up.and.down.righttriangle.up.righttriangle.down")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(appState.activeImage == nil)
            .help("Flip Vertical")

            // Transform reset button - always visible, disabled when no transform
            Button {
                appState.resetActiveImageTransform()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .foregroundColor(appState.activeImageTransform.isIdentity ? Color.secondary : Color.orange)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(appState.activeImage == nil || appState.activeImageTransform.isIdentity)
            .help("Reset Transform")
        }
    }
}

// MARK: - Export Section

struct ExportSectionView: View {
    @Environment(AppState.self) private var appState
    @State private var coordinator = ExportCoordinator()

    private var imagesToProcess: [ImageItem] {
        appState.selectedImageIDs.isEmpty ? appState.images : appState.selectedImages
    }

    var body: some View {
        @Bindable var state = appState

        VStack(alignment: .leading, spacing: 12) {
            // Format buttons
            VStack(spacing: 4) {
                Text("Format")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    ForEach(ExportFormat.allCases) { fmt in
                        Button {
                            appState.exportSettings.format = fmt
                            appState.markCustomSettings()
                        } label: {
                            Text(fmt.rawValue)
                                .font(.system(size: 10, weight: .medium))
                                .frame(minWidth: 36, minHeight: 22)
                        }
                        .buttonStyle(.bordered)
                        .tint(appState.exportSettings.format == fmt ? .accentColor : .secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Divider()

            // Naming buttons
            VStack(spacing: 4) {
                Text("Naming")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    ForEach(RenameMode.allCases) { mode in
                        Button {
                            appState.exportSettings.renameSettings.mode = mode
                            appState.markCustomSettings()
                        } label: {
                            Text(mode.rawValue)
                                .font(.system(size: 10, weight: .medium))
                                .frame(minHeight: 22)
                                .padding(.horizontal, 8)
                        }
                        .buttonStyle(.bordered)
                        .tint(appState.exportSettings.renameSettings.mode == mode ? .accentColor : .secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            // Output preview
            if let firstImage = appState.images.first {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(appState.exportSettings.outputFilename(for: firstImage.url))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            // Warning if nothing to export
            if !appState.canExport && !appState.images.isEmpty && !appState.isProcessing {
                Text("Apply crop, transform, or resize to export")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            // Export options (always visible)
            Divider()
            ExportOptionsExpandedView()

            // Export button - at bottom with padding
            Spacer().frame(height: 8)

            Button {
                coordinator.selectOutputFolderAndProcess(images: imagesToProcess)
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.down.fill")
                    Text(appState.selectedImageIDs.isEmpty
                         ? "Export All (\(appState.images.count))"
                         : "Export Selected (\(appState.selectedImageIDs.count))")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!appState.canExport)

            // Progress indicator
            if appState.isProcessing {
                VStack(spacing: 4) {
                    ProgressView(value: appState.processingProgress)
                        .progressViewStyle(.linear)
                    Text("Exporting \(Int(appState.processingProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear { coordinator.setAppState(appState) }
        .exportSheets(coordinator: coordinator, appState: appState, imagesToProcess: imagesToProcess)
    }
}

// MARK: - Export Options Expanded

struct ExportOptionsExpandedView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        VStack(alignment: .leading, spacing: 12) {
            // Quality slider (for JPEG/HEIC/WebP)
            if appState.exportSettings.format.supportsCompression {
                HStack {
                    Text("Quality")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { appState.exportSettings.quality },
                        set: { appState.exportSettings.quality = $0; appState.markCustomSettings() }
                    ), in: 0.1...1.0, step: 0.05)
                    .controlSize(.small)
                    Text("\(Int(appState.exportSettings.quality * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 35)
                }
            }

            // Suffix field (when using Keep Original naming)
            if appState.exportSettings.renameSettings.mode == .keepOriginal {
                HStack {
                    Text("Suffix")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField("_cropped", text: Binding(
                        get: { appState.exportSettings.suffix },
                        set: { appState.exportSettings.suffix = $0; appState.markCustomSettings() }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                }
            }

            // Pattern field (when using Pattern naming)
            if appState.exportSettings.renameSettings.mode == .pattern {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Pattern")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        TextField("{name}_{counter}", text: Binding(
                            get: { appState.exportSettings.renameSettings.pattern },
                            set: { appState.exportSettings.renameSettings.pattern = $0; appState.markCustomSettings() }
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
                }
            }

            Divider()

            // Resize settings
            ResizeSettingsSection()

            Divider()

            // Watermark settings
            WatermarkSettingsSection()

            Divider()

            // File size estimate (always visible when images loaded)
            if !appState.images.isEmpty {
                FileSizeEstimateView()
                    .frame(maxWidth: .infinity)
                
                Divider()
            }
        }
    }
}

// MARK: - Collapsible Section

struct CollapsibleSection<Content: View>: View {
    let title: String
    let icon: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Content
            if isExpanded {
                content()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            Divider()
        }
    }
}

struct ResolutionWarningView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Resolution Mismatch", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.yellow)

            if let majority = appState.majorityResolution {
                Text("\(appState.mismatchedImages.count) image(s) differ from the majority resolution of \(Int(majority.width))×\(Int(majority.height))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // List mismatched files
            VStack(alignment: .leading, spacing: 4) {
                ForEach(appState.mismatchedImages.prefix(3)) { item in
                    HStack(spacing: 4) {
                        Image(systemName: "photo")
                            .font(.caption2)
                        Text(item.filename)
                            .font(.caption2)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int(item.originalSize.width))×\(Int(item.originalSize.height))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if appState.mismatchedImages.count > 3 {
                    Text("...and \(appState.mismatchedImages.count - 3) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }
}

struct ImageInfoView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Images:")
                Spacer()
                Text("\(appState.images.count)")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)

            if let majority = appState.majorityResolution {
                HStack {
                    Text("Resolution:")
                    Spacer()
                    Text("\(Int(majority.width)) × \(Int(majority.height))")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }

            if appState.cropSettings.hasAnyCrop, let majority = appState.majorityResolution {
                let newSize = appState.cropSettings.croppedSize(from: majority)
                HStack {
                    Text("Output size:")
                    Spacer()
                    Text("\(Int(newSize.width)) × \(Int(newSize.height))")
                        .foregroundStyle(.green)
                }
                .font(.callout)
            }
        }
    }
}

struct KeyboardShortcutsContentView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left column: Navigation & Crop
            VStack(alignment: .leading, spacing: 4) {
                Text("Navigation & Crop")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 2)

                ShortcutRow(keys: "←  →", description: "Navigate")
                ShortcutRow(keys: "⇧ Arrow", description: "Adjust crop")
                ShortcutRow(keys: "⇧⌥ Arrow", description: "Uncrop")
                ShortcutRow(keys: "⇧⌃ Arrow", description: "×10 adjust")
                ShortcutRow(keys: "⌃ Drag", description: "Snap grid")
                ShortcutRow(keys: "⌥ Drag", description: "Bypass snap")
                ShortcutRow(keys: "S", description: "Toggle snap")
                ShortcutRow(keys: "Dbl-click", description: "Reset")
            }
            .frame(width: 190, alignment: .leading)

            Divider()
                .padding(.horizontal, 8)

            // Right column: Zoom
            VStack(alignment: .leading, spacing: 4) {
                Text("Zoom")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 2)

                ZoomShortcutRow(keys: "⌘1", description: "100%")
                ZoomShortcutRow(keys: "⌘2", description: "Fit")
                ZoomShortcutRow(keys: "⌘3", description: "Width")
                ZoomShortcutRow(keys: "⌘4", description: "Height")
            }

            Spacer()
        }
    }
}

struct ShortcutRow: View {
    let keys: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Text(keys)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: 70, alignment: .leading)

            Text(description)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct ZoomShortcutRow: View {
    let keys: String
    let description: String

    var body: some View {
        HStack(spacing: 10) {
            Text(keys)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: 24, alignment: .leading)

            Text(description)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - AppKit Segmented Control (bypasses Liquid Glass)

struct ZoomPicker: NSViewRepresentable {
    @Binding var selection: ZoomMode

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.segmentCount = ZoomMode.allCases.count
        control.segmentStyle = .texturedRounded
        control.trackingMode = .selectOne

        for (index, mode) in ZoomMode.allCases.enumerated() {
            control.setLabel(mode.rawValue, forSegment: index)
            control.setWidth(0, forSegment: index) // Auto-size
        }

        control.target = context.coordinator
        control.action = #selector(Coordinator.segmentChanged(_:))

        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        if let index = ZoomMode.allCases.firstIndex(of: selection) {
            control.selectedSegment = index
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    class Coordinator: NSObject {
        var selection: Binding<ZoomMode>

        init(selection: Binding<ZoomMode>) {
            self.selection = selection
        }

        @MainActor @objc func segmentChanged(_ sender: NSSegmentedControl) {
            let index = sender.selectedSegment
            if index >= 0 && index < ZoomMode.allCases.count {
                selection.wrappedValue = ZoomMode.allCases[index]
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
        .frame(width: 1000, height: 700)
}
