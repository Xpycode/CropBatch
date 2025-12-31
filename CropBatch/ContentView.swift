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
                    Picker("Zoom", selection: Binding(
                        get: { appState.zoomMode },
                        set: { appState.zoomMode = $0 }
                    )) {
                        ForEach(ZoomMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
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
    @AppStorage("sidebar.autoProcessExpanded") private var autoProcessExpanded = false
    @AppStorage("sidebar.shortcutsExpanded") private var shortcutsExpanded = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Resolution warning (always visible if needed)
                if appState.hasResolutionMismatch {
                    ResolutionWarningView()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    Divider()
                }

                // ═══════════════════════════════════════
                // CROP - Primary section, always visible
                // ═══════════════════════════════════════
                CropSectionView()

                Divider()

                // ═══════════════════════════════════════
                // TRANSFORM - Shelved (breaks crop state)
                // ═══════════════════════════════════════
                #if false
                TransformRowView()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                Divider()
                #endif

                // ═══════════════════════════════════════
                // EXPORT - Prominent action area
                // ═══════════════════════════════════════
                ExportSectionView()

                Divider()

                // ═══════════════════════════════════════
                // ADVANCED - Collapsed by default
                // ═══════════════════════════════════════
                #if false // Folder Watch - shelved for simplicity
                CollapsibleSection(title: "Folder Watch", icon: "folder.badge.gearshape", isExpanded: $autoProcessExpanded) {
                    FolderWatchView()
                }
                #endif

                CollapsibleSection(title: "Keyboard Shortcuts", icon: "keyboard", isExpanded: $shortcutsExpanded) {
                    KeyboardShortcutsContentView()
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
            // NOTE: Blur tool hidden - coordinate transform issues with rotations
            // See docs/blur-feature-status.md for details. Code preserved for future.
            HStack(spacing: 0) {
                ForEach(EditorTool.allCases.filter { $0 != .blur }) { tool in
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

            // Output size badge (for crop tool)
            if appState.currentTool == .crop, let majority = appState.majorityResolution {
                let newSize = appState.cropSettings.croppedSize(from: majority)
                Text("\(Int(newSize.width))×\(Int(newSize.height))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(appState.cropSettings.hasAnyCrop ? .green : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
                    .frame(maxWidth: .infinity)
            }

            // Tool-specific controls
            if appState.currentTool == .crop {
                // MARK: Crop Tool Controls

                // Preset picker - shelved for simplicity
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

            TextField("0", value: $value, format: .number)
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
    @State private var showReviewSheet = false
    @State private var pendingOutputDirectory: URL?
    @State private var showErrorAlert = false
    @State private var exportError: String?
    @State private var showSuccessAlert = false
    @State private var exportedCount = 0

    // Overwrite handling
    @State private var showOverwriteDialog = false
    @State private var existingFilesCount = 0
    @State private var pendingExportImages: [ImageItem] = []
    @State private var pendingExportDirectory: URL?
    @State private var dialogPresentationID = UUID()  // Forces dialog rebuild on each presentation

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
                selectOutputFolder()
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
        .sheet(isPresented: $showReviewSheet) {
            if let outputDir = pendingOutputDirectory {
                BatchReviewView(images: imagesToProcess, outputDirectory: outputDir) { selectedImages in
                    Task {
                        await processImages(selectedImages, to: outputDir)
                    }
                }
                .environment(appState)
            }
        }
        .alert("Export Complete", isPresented: $showSuccessAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Successfully exported \(exportedCount) images")
        }
        .alert("Export Failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "Unknown error")
        }
        .confirmationDialog(
            "Overwrite Existing Files?",
            isPresented: $showOverwriteDialog,
            titleVisibility: .visible
        ) {
            // Capture values BEFORE the Task to avoid race conditions
            // (dialog dismissal may clear state before Task starts)
            let images = pendingExportImages
            let directory = pendingExportDirectory

            Button("Overwrite", role: .destructive) {
                guard let dir = directory else { return }
                Task {
                    await executeExport(images, to: dir, rename: false)
                }
            }
            Button("Rename (add _1, _2...)") {
                guard let dir = directory else { return }
                Task {
                    await executeExport(images, to: dir, rename: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(existingFilesCount) file\(existingFilesCount == 1 ? "" : "s") already exist\(existingFilesCount == 1 ? "s" : "") in the destination folder.")
        }
        .id(dialogPresentationID)  // Force SwiftUI to rebuild dialog content on each presentation
        .onChange(of: showOverwriteDialog) { _, isShowing in
            // Clear pending state when dialog closes
            if !isShowing {
                pendingExportImages = []
                pendingExportDirectory = nil
            }
        }
    }

    private func selectOutputFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Export Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let outputDirectory = panel.url else { return }
            Task {
                await processImages(imagesToProcess, to: outputDirectory)
            }
        }
    }

    private func processImages(_ images: [ImageItem], to outputDirectory: URL) async {
        // Check for existing files before exporting
        var settings = appState.exportSettings
        settings.outputDirectory = .custom(outputDirectory)
        let existingFiles = settings.findExistingFiles(items: images)

        if !existingFiles.isEmpty {
            // Show confirmation dialog
            existingFilesCount = existingFiles.count
            pendingExportImages = images
            pendingExportDirectory = outputDirectory
            dialogPresentationID = UUID()  // Force dialog content rebuild
            showOverwriteDialog = true
        } else {
            // No conflicts, proceed directly
            await executeExport(images, to: outputDirectory, rename: false)
        }
    }

    private func executeExport(_ images: [ImageItem], to outputDirectory: URL, rename: Bool) async {
        do {
            let results: [URL]

            if rename {
                results = try await appState.processAndExportWithRename(images: images, to: outputDirectory)
            } else {
                results = try await appState.processAndExport(images: images, to: outputDirectory)
            }

            exportedCount = results.count
            showSuccessAlert = true
        } catch {
            exportError = error.localizedDescription
            showErrorAlert = true
        }
        // Note: pending state is cleared by .onChange(of: showOverwriteDialog)
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

#Preview {
    ContentView()
        .environment(AppState())
        .frame(width: 1000, height: 700)
}
