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
    @AppStorage("sidebar.gridSplitExpanded") private var gridSplitExpanded = false
    @AppStorage("sidebar.shortcutsExpanded") private var shortcutsExpanded = false

    var body: some View {
        @Bindable var state = appState

        VStack(spacing: 0) {
            // Scrollable content using Form for inspector-style layout
            Form {
                // ═══════════════════════════════════════
                // TOOL SELECTOR - Crop / Blur tabs
                // ═══════════════════════════════════════
                Section {
                    Picker("Tool", selection: $state.currentTool) {
                        ForEach(EditorTool.allCases) { tool in
                            Label(tool.rawValue, systemImage: tool.icon).tag(tool)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                // Resolution warning (always visible if needed)
                if appState.hasResolutionMismatch {
                    Section {
                        ResolutionWarningView()
                    }
                }

                // ═══════════════════════════════════════
                // TOOL-SPECIFIC CONTROLS
                // ═══════════════════════════════════════
                if appState.currentTool == .crop {
                    // CROP - Primary controls
                    Section {
                        CropControlsView()
                    }

                    // ASPECT GUIDE - Quick access
                    Section {
                        AspectGuideView()
                    }

                    // TRANSFORM - Rotation/Flip
                    Section {
                        TransformRowView()
                    }
                } else if appState.currentTool == .blur {
                    // BLUR - Settings panel
                    Section {
                        BlurToolSettingsPanel()
                    }
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
                // GRID SPLIT - Toggle in header
                // ═══════════════════════════════════════
                Section(isExpanded: $gridSplitExpanded) {
                    GridSplitOptionsView()
                } header: {
                    HStack {
                        Text("Grid Split")
                        Spacer()
                        Toggle("", isOn: $state.exportSettings.gridSettings.isEnabled)
                            .labelsHidden()
                            .controlSize(.small)
                            .onChange(of: appState.exportSettings.gridSettings.isEnabled) { _, isEnabled in
                                if isEnabled {
                                    withAnimation { gridSplitExpanded = true }
                                }
                            }
                    }
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

#Preview {
    ContentView()
        .environment(AppState())
        .frame(width: 1000, height: 700)
}
