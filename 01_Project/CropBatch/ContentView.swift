import SwiftUI
import UniformTypeIdentifiers

// MARK: - Sidebar Tab

enum SidebarTab: String, CaseIterable {
    case crop, effects, export
}

// MARK: - Content View

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showShortcutsPopover = false

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
            // Left: Undo/Redo
            ToolbarItemGroup(placement: .navigation) {
                if !appState.images.isEmpty {
                    HStack {
                        Button { appState.undo() } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(FCPToolbarButtonStyle())
                        .disabled(!appState.canUndo)
                        .help("Undo (⌘Z)")

                        Button { appState.redo() } label: {
                            Image(systemName: "arrow.uturn.forward")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(FCPToolbarButtonStyle())
                        .disabled(!appState.canRedo)
                        .help("Redo (⇧⌘Z)")
                    }
                    .buttonStyle(.borderless)
                }
            }

            // Center: Zoom controls
            ToolbarItem(placement: .principal) {
                if !appState.images.isEmpty {
                    ZoomPicker(selection: Binding(
                        get: { appState.zoomMode },
                        set: { appState.zoomMode = $0 }
                    ))
                }
            }

            // Right side: buttons
            ToolbarItemGroup(placement: .primaryAction) {
                if !appState.images.isEmpty {
                    HStack {
                        Button { showShortcutsPopover.toggle() } label: {
                            Image(systemName: "questionmark.circle")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(FCPToolbarButtonStyle())
                        .popover(isPresented: $showShortcutsPopover) {
                            KeyboardShortcutsContentView()
                                .padding()
                        }
                        .help("Keyboard Shortcuts")

                        Button {
                            appState.showImportPanel()
                        } label: {
                            Image(systemName: "plus")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(FCPToolbarButtonStyle())

                        Button {
                            appState.clearAll()
                        } label: {
                            Image(systemName: "trash")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(FCPToolbarButtonStyle())
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .toolbarRole(.editor)
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

// MARK: - Sidebar View

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    // Tab persistence
    @AppStorage("sidebar.selectedTab") private var selectedTab = SidebarTab.crop.rawValue

    // Collapsed state persistence
    @AppStorage("sidebar.blurExpanded") private var blurExpanded = false
    @AppStorage("sidebar.snapExpanded") private var snapExpanded = false
    @AppStorage("sidebar.watermarkExpanded") private var watermarkExpanded = false
    @AppStorage("sidebar.gridSplitExpanded") private var gridSplitExpanded = false
    @AppStorage("sidebar.folderWatcherExpanded") private var folderWatcherExpanded = false

    private var selectedTabBinding: Binding<SidebarTab> {
        Binding(
            get: { SidebarTab(rawValue: selectedTab) ?? .crop },
            set: { selectedTab = $0.rawValue }
        )
    }

    var body: some View {
        @Bindable var state = appState

        VStack(spacing: 0) {
            // Tab picker — centered above scrollable form
            AppKitSegmented(
                items: [("Crop", SidebarTab.crop), ("Effects", SidebarTab.effects), ("Export", SidebarTab.export)],
                selection: selectedTabBinding
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Scrollable content using Form for inspector-style layout
            Form {
                // Resolution warning (always visible, above tabs)
                if appState.hasResolutionMismatch {
                    Section {
                        ResolutionWarningView()
                    }
                }

                // ═══════════════════════════════════════
                // CROP TAB
                // ═══════════════════════════════════════
                if selectedTab == SidebarTab.crop.rawValue {
                    Section {
                        CropControlsView()
                    }

                    Section {
                        AspectGuideView()
                    }

                    Section {
                        TransformRowView()
                    }

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
                }

                // ═══════════════════════════════════════
                // EFFECTS TAB
                // ═══════════════════════════════════════
                if selectedTab == SidebarTab.effects.rawValue {
                    Section(isExpanded: $blurExpanded) {
                        BlurToolSettingsPanel()
                    } header: {
                        HStack {
                            Text("Blur Regions")
                            Spacer()
                            Toggle("", isOn: $state.isBlurDrawingEnabled)
                                .labelsHidden()
                                .controlSize(.small)
                                .onChange(of: appState.isBlurDrawingEnabled) { _, isEnabled in
                                    if isEnabled {
                                        withAnimation { blurExpanded = true }
                                    }
                                }
                        }
                    }

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
                }

                // ═══════════════════════════════════════
                // EXPORT TAB
                // ═══════════════════════════════════════
                if selectedTab == SidebarTab.export.rawValue {
                    Section {
                        ExportFormatView()
                    }

                    Section {
                        QualityResizeView()
                    }

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

                    Section(isExpanded: $folderWatcherExpanded) {
                        FolderWatchView()
                    } header: {
                        HStack {
                            Text("Folder Watcher")
                            Spacer()
                            if FolderWatcher.shared.isWatching {
                                Circle().fill(.green).frame(width: 8, height: 8)
                            }
                        }
                    }
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
